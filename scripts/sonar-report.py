#!/usr/bin/env python3
# =============================================================================
# sonar-report.py — Verdict de quality gate et export des preuves SonarQube
# =============================================================================
#
# BUT
#   Attendre la fin du traitement d'une analyse SonarQube, en récupérer le
#   verdict de quality gate, et exporter des PREUVES exploitables : liste des
#   vulnérabilités, des security hotspots et des mesures de qualité, au format
#   JSON (brut, rejouable) et Markdown (lisible), plus une ligne d'historique
#   CSV permettant la comparaison avant/après entre deux exécutions.
#
#   Ce dernier point est la raison d'être du script. Le serveur SonarQube du
#   pipeline est éphémère : son tableau de bord disparaît avec le job, et avec
#   lui la possibilité de mesurer une TENDANCE. L'historique CSV versionné
#   restitue cette capacité — c'est lui qui documentera le cycle
#   « vulnérabilités identifiées → priorisées → corrigées » attendu au rapport
#   de performance, et il est plus solide qu'une capture d'écran : il est
#   daté, rattaché à un commit, et comparable automatiquement.
#
# FONCTIONNEMENT
#   1. Lit `.scannerwork/report-task.txt` (produit par le scanner) pour obtenir
#      la clé de projet et l'identifiant de tâche, ou accepte ces valeurs en
#      paramètres.
#   2. Interroge /api/ce/task jusqu'à ce que le traitement serveur soit terminé
#      (l'analyse est asynchrone : interroger la quality gate immédiatement
#      après le scanner renverrait le résultat de l'analyse PRÉCÉDENTE).
#   3. Récupère le statut de quality gate et le détail de ses conditions.
#   4. Récupère les issues (bugs, vulnérabilités, code smells), les security
#      hotspots et les mesures principales.
#   5. Écrit les preuves : JSON horodaté, RESUME.md, et une ligne dans
#      historique.csv.
#   6. Sort en code 8 si la quality gate a échoué (sauf --sans-gate).
#
# PARAMÈTRES
#   -u, --url <url>             URL du serveur SonarQube  (défaut : http://localhost:9000)
#   -k, --cle <projectKey>      Clé du projet             (défaut : lue dans le rapport)
#   -r, --rapport-tache <fic.>  Chemin de report-task.txt (défaut : .scannerwork/report-task.txt)
#   -s, --sortie <répertoire>   Répertoire des preuves    (défaut : docs/captures/sonarqube)
#   -d, --delai <secondes>      Délai max d'attente       (défaut : 300)
#       --sans-gate             N'échoue pas si la quality gate échoue
#   -v, --verbeux               Journalisation détaillée
#
#   Variables d'environnement lues :
#     SONAR_TOKEN      jeton d'analyse (requis) — jamais journalisé
#     GITHUB_SHA       commit analysé, reporté dans l'historique
#     GITHUB_RUN_ID    exécution de pipeline associée
#
# CONDITIONS D'EXÉCUTION
#   - Python >= 3.8, AUCUNE dépendance externe (bibliothèque standard seule).
#   - Serveur SonarQube joignable et analyse déjà soumise.
#   - SONAR_TOKEN valide, transmis par l'environnement et non en argument :
#     les arguments de ligne de commande sont visibles dans la table des
#     processus, pas les variables d'environnement d'un processus tiers.
#   - Droits d'écriture sur le répertoire de sortie.
#   - Codes de sortie : 0 quality gate passée · 1 erreur d'exécution
#     · 2 prérequis manquant · 3 paramètre invalide · 8 quality gate en échec
#
# EXEMPLES
#   SONAR_TOKEN=xxx python3 scripts/sonar-report.py
#   SONAR_TOKEN=xxx python3 scripts/sonar-report.py --sans-gate --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

VERBEUX = False

# Mesures récupérées pour l'historique. Le choix est délibérément restreint :
# ce sont celles qui parlent à un lecteur non technique (rapport de
# performance) ou qui pilotent la quality gate.
METRIQUES = [
    "bugs",
    "vulnerabilities",
    "security_hotspots",
    "code_smells",
    "coverage",
    "duplicated_lines_density",
    "ncloc",
    "sqale_index",
    "reliability_rating",
    "security_rating",
    "sqale_rating",
]

NOTES = {"1.0": "A", "2.0": "B", "3.0": "C", "4.0": "D", "5.0": "E"}


def journal(message: str) -> None:
    if VERBEUX:
        print(f"[DEBUG] {message}", file=sys.stderr)


def info(message: str) -> None:
    print(f"[INFO]  {message}", file=sys.stderr)


def avertir(message: str) -> None:
    print(f"[AVERT] {message}", file=sys.stderr)


def erreur(message: str) -> None:
    print(f"[ERREUR] {message}", file=sys.stderr)


# -----------------------------------------------------------------------------
# Accès à l'API SonarQube
# -----------------------------------------------------------------------------


class ClientSonar:
    """Client minimal de l'API SonarQube (bibliothèque standard uniquement).

    L'authentification par jeton se fait en Basic avec le jeton en identifiant
    et un mot de passe vide — forme historique acceptée par toutes les versions,
    là où l'en-tête Bearer n'est reconnu que par les versions récentes.
    """

    def __init__(self, url: str, jeton: str) -> None:
        self.url = url.rstrip("/")
        self._entete = base64.b64encode(f"{jeton}:".encode()).decode()

    def get(self, chemin: str, **parametres) -> dict | None:
        adresse = f"{self.url}{chemin}"
        if parametres:
            adresse += "?" + urllib.parse.urlencode(parametres)
        requete = urllib.request.Request(adresse)
        requete.add_header("Authorization", f"Basic {self._entete}")
        try:
            with urllib.request.urlopen(requete, timeout=30) as reponse:
                return json.loads(reponse.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            avertir(f"API {chemin} : HTTP {err.code}")
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as err:
            avertir(f"API {chemin} injoignable : {err}")
        return None

    def paginer(self, chemin: str, cle: str, **parametres) -> list:
        """Parcourt toutes les pages d'un point d'entrée paginé.

        SonarQube plafonne à 500 éléments par page ; sans pagination, une base
        de code volumineuse verrait ses issues silencieusement tronquées — et
        une preuve tronquée n'est pas une preuve.
        """
        elements: list = []
        page = 1
        while page <= 20:  # garde-fou : 10 000 éléments au maximum
            donnees = self.get(chemin, p=page, ps=500, **parametres)
            if not donnees:
                break
            lot = donnees.get(cle, [])
            elements.extend(lot)
            total = donnees.get("paging", {}).get("total", donnees.get("total", len(elements)))
            if len(elements) >= total or not lot:
                break
            page += 1
        return elements


# -----------------------------------------------------------------------------
# Lecture du rapport de tâche
# -----------------------------------------------------------------------------


def lire_rapport_tache(chemin: Path) -> dict[str, str]:
    """Analyse le fichier report-task.txt produit par le scanner."""
    valeurs: dict[str, str] = {}
    if not chemin.is_file():
        journal(f"rapport de tâche absent : {chemin}")
        return valeurs
    for ligne in chemin.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in ligne:
            cle, _, valeur = ligne.partition("=")
            valeurs[cle.strip()] = valeur.strip()
    journal(f"rapport de tâche : {sorted(valeurs)}")
    return valeurs


def attendre_analyse(client: ClientSonar, task_id: str, delai: int) -> str | None:
    """Attend la fin du traitement serveur et retourne l'identifiant d'analyse.

    Sans cette attente, la quality gate interrogée serait celle de l'analyse
    précédente : le pipeline validerait un état qui n'est plus le sien.
    """
    info(f"attente du traitement de l'analyse (délai max : {delai}s)…")
    ecoule = 0
    while ecoule < delai:
        donnees = client.get("/api/ce/task", id=task_id)
        statut = (donnees or {}).get("task", {}).get("status", "INCONNU")
        journal(f"…statut de la tâche : {statut} ({ecoule}s)")
        if statut == "SUCCESS":
            info(f"analyse traitée après {ecoule}s")
            return (donnees or {}).get("task", {}).get("analysisId")
        if statut in ("FAILED", "CANCELED"):
            erreur(f"le serveur a rejeté l'analyse (statut {statut})")
            return None
        time.sleep(5)
        ecoule += 5
    erreur(f"analyse non traitée dans le délai de {delai}s")
    return None


def attendre_projet(client: ClientSonar, cle: str, delai: int) -> bool:
    """Repli lorsque l'identifiant de tâche n'a pas pu être lu.

    Interroge la file de traitement du projet : l'analyse est terminée quand
    la file est vide et que la dernière tâche s'est achevée avec succès.
    Moins précis qu'un suivi par identifiant, mais suffisant ici puisqu'une
    seule analyse est soumise par exécution de pipeline.
    """
    info(f"attente du traitement du projet « {cle} » (délai max : {delai}s)…")
    ecoule = 0
    while ecoule < delai:
        donnees = client.get("/api/ce/component", component=cle) or {}
        file_attente = donnees.get("queue", [])
        courante = donnees.get("current", {})
        statut = courante.get("status")
        journal(f"…file : {len(file_attente)} · tâche courante : {statut} ({ecoule}s)")
        if not file_attente and statut == "SUCCESS":
            info(f"analyse traitée après {ecoule}s")
            return True
        if not file_attente and statut in ("FAILED", "CANCELED"):
            erreur(f"le serveur a rejeté l'analyse (statut {statut})")
            return False
        time.sleep(5)
        ecoule += 5
    erreur(f"analyse non traitée dans le délai de {delai}s")
    return False


# -----------------------------------------------------------------------------
# Rendu des preuves
# -----------------------------------------------------------------------------


def note(valeur: str | None) -> str:
    return NOTES.get(str(valeur), str(valeur or "-"))


def compter(elements: list, champ: str) -> dict[str, int]:
    comptes: dict[str, int] = {}
    for element in elements:
        cle = str(element.get(champ, "INCONNU"))
        comptes[cle] = comptes.get(cle, 0) + 1
    return comptes


def rendre_markdown(donnees: dict) -> str:
    mesures = donnees["mesures"]
    gate = donnees["quality_gate"]
    issues = donnees["issues"]
    hotspots = donnees["hotspots"]

    icone = "✅" if gate.get("status") == "OK" else "❌"
    lignes: list[str] = [
        "# Analyse SonarQube — MicroCRM (Orion)",
        "",
        f"> Analyse du **{donnees['horodatage']}** · commit `{donnees['commit']}` · "
        f"projet `{donnees['cle_projet']}`",
        "",
        f"## {icone} Quality gate : **{gate.get('status', 'INCONNU')}**",
        "",
    ]

    conditions = gate.get("conditions", [])
    if conditions:
        lignes += ["| Condition | Seuil | Valeur | Verdict |", "|---|---|---|---|"]
        for condition in conditions:
            etat = "✅" if condition.get("status") == "OK" else "❌"
            lignes.append(
                f"| `{condition.get('metricKey', '?')}` "
                f"| {condition.get('comparator', '')} {condition.get('errorThreshold', '?')} "
                f"| {condition.get('actualValue', '?')} | {etat} |"
            )
        lignes.append("")

    lignes += [
        "## Mesures de qualité",
        "",
        "| Indicateur | Valeur |",
        "|---|---|",
        f"| Bugs | {mesures.get('bugs', '-')} |",
        f"| **Vulnérabilités** | **{mesures.get('vulnerabilities', '-')}** |",
        f"| **Security hotspots** | **{mesures.get('security_hotspots', '-')}** |",
        f"| Code smells | {mesures.get('code_smells', '-')} |",
        f"| Couverture | {mesures.get('coverage', '-')} % |",
        f"| Duplication | {mesures.get('duplicated_lines_density', '-')} % |",
        f"| Lignes de code | {mesures.get('ncloc', '-')} |",
        f"| Note de fiabilité | {note(mesures.get('reliability_rating'))} |",
        f"| Note de sécurité | {note(mesures.get('security_rating'))} |",
        f"| Note de maintenabilité | {note(mesures.get('sqale_rating'))} |",
        "",
    ]

    lignes += ["## Répartition des issues", ""]
    par_severite = compter(issues, "severity")
    par_type = compter(issues, "type")
    if issues:
        lignes += ["| Type | Nombre |", "|---|---|"]
        lignes += [f"| {t} | {n} |" for t, n in sorted(par_type.items(), key=lambda x: -x[1])]
        lignes += ["", "| Sévérité | Nombre |", "|---|---|"]
        lignes += [f"| {s} | {n} |" for s, n in sorted(par_severite.items(), key=lambda x: -x[1])]
        lignes.append("")
    else:
        lignes += ["_Aucune issue remontée._", ""]

    # Les vulnérabilités sont listées nominativement : c'est la matière du
    # cycle « identifiées → priorisées → corrigées ».
    vulnerabilites = [i for i in issues if i.get("type") == "VULNERABILITY"]
    if vulnerabilites:
        lignes += ["## Vulnérabilités détectées", "", "| Sévérité | Règle | Fichier | Ligne | Message |", "|---|---|---|---|---|"]
        for issue in sorted(vulnerabilites, key=lambda i: str(i.get("severity"))):
            composant = str(issue.get("component", "")).split(":")[-1]
            lignes.append(
                f"| {issue.get('severity', '?')} | `{issue.get('rule', '?')}` "
                f"| `{composant}` | {issue.get('line', '-')} "
                f"| {str(issue.get('message', '')).replace('|', '/')} |"
            )
        lignes.append("")

    lignes += [f"## Security hotspots ({len(hotspots)})", ""]
    if hotspots:
        lignes += ["| Probabilité | Catégorie | Fichier | Ligne | Message |", "|---|---|---|---|---|"]
        for hotspot in sorted(hotspots, key=lambda h: str(h.get("vulnerabilityProbability"))):
            composant = str(hotspot.get("component", "")).split(":")[-1]
            lignes.append(
                f"| {hotspot.get('vulnerabilityProbability', '?')} "
                f"| {hotspot.get('securityCategory', '?')} | `{composant}` "
                f"| {hotspot.get('line', '-')} "
                f"| {str(hotspot.get('message', '')).replace('|', '/')} |"
            )
        lignes.append("")
        lignes += [
            "> **Rappel** : un security hotspot n'est pas une vulnérabilité avérée, mais un point du",
            "> code où une décision de sécurité a été prise et doit être **revue par un humain**. Le",
            "> critère d'évaluation porte sur leur revue, pas sur leur disparition.",
            "",
        ]
    else:
        lignes += ["_Aucun security hotspot détecté._", ""]

    lignes += [
        "---",
        "",
        "<sub>Généré par `scripts/sonar-report.py`. Le serveur SonarQube du pipeline étant éphémère,",
        "ce document et `historique.csv` constituent la preuve conservée de l'analyse.</sub>",
    ]
    return "\n".join(lignes)


def ecrire_historique(fichier: Path, donnees: dict) -> None:
    """Ajoute une ligne à l'historique CSV — support de la comparaison avant/après."""
    mesures = donnees["mesures"]
    ligne = {
        "horodatage": donnees["horodatage"],
        "commit": donnees["commit"],
        "execution": donnees["execution"],
        "quality_gate": donnees["quality_gate"].get("status", "-"),
        "bugs": mesures.get("bugs", ""),
        "vulnerabilites": mesures.get("vulnerabilities", ""),
        "security_hotspots": mesures.get("security_hotspots", ""),
        "code_smells": mesures.get("code_smells", ""),
        "couverture": mesures.get("coverage", ""),
        "duplication": mesures.get("duplicated_lines_density", ""),
        "lignes_de_code": mesures.get("ncloc", ""),
        "note_securite": note(mesures.get("security_rating")),
        "note_fiabilite": note(mesures.get("reliability_rating")),
        "note_maintenabilite": note(mesures.get("sqale_rating")),
    }
    nouveau = not fichier.exists()
    with open(fichier, "a", encoding="utf-8", newline="") as flux:
        redacteur = csv.DictWriter(flux, fieldnames=list(ligne))
        if nouveau:
            redacteur.writeheader()
        redacteur.writerow(ligne)


# -----------------------------------------------------------------------------
# Point d'entrée
# -----------------------------------------------------------------------------


def analyser_arguments(argv: list[str]) -> argparse.Namespace:
    analyseur = argparse.ArgumentParser(
        prog="sonar-report.py",
        description="Verdict de quality gate et export des preuves SonarQube.",
    )
    analyseur.add_argument("-u", "--url", default="http://localhost:9000")
    analyseur.add_argument("-k", "--cle")
    analyseur.add_argument("-r", "--rapport-tache", default=".scannerwork/report-task.txt")
    analyseur.add_argument("-s", "--sortie", default="docs/captures/sonarqube")
    analyseur.add_argument("-d", "--delai", type=int, default=300)
    analyseur.add_argument("--sans-gate", action="store_true")
    analyseur.add_argument("-v", "--verbeux", action="store_true")
    return analyseur.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    global VERBEUX
    args = analyser_arguments(argv if argv is not None else sys.argv[1:])
    VERBEUX = args.verbeux

    jeton = os.environ.get("SONAR_TOKEN")
    if not jeton:
        erreur("SONAR_TOKEN absent de l'environnement.")
        return 2

    rapport = lire_rapport_tache(Path(args.rapport_tache))
    cle_projet = args.cle or rapport.get("projectKey")
    if not cle_projet:
        erreur("clé de projet introuvable : fournissez --cle ou --rapport-tache.")
        return 3

    client = ClientSonar(args.url, jeton)

    task_id = rapport.get("ceTaskId")
    if task_id:
        if attendre_analyse(client, task_id, args.delai) is None:
            return 1
    elif not attendre_projet(client, cle_projet, args.delai):
        # Repli : sans identifiant de tâche, on attend que la file de
        # traitement du PROJET se vide. Sans cette attente, la quality gate
        # interrogée serait celle de l'analyse précédente — voire inexistante.
        return 1

    # Le statut est demandé par clé de projet plutôt que par analysisId : la
    # réponse reste correcte même si l'identifiant d'analyse n'a pas pu être lu.
    gate = (client.get("/api/qualitygates/project_status", projectKey=cle_projet) or {}).get(
        "projectStatus", {}
    )

    brut = client.get("/api/measures/component", component=cle_projet, metricKeys=",".join(METRIQUES))
    mesures = {
        m["metric"]: m.get("value")
        for m in (brut or {}).get("component", {}).get("measures", [])
    }

    issues = client.paginer("/api/issues/search", "issues", componentKeys=cle_projet, resolved="false")
    hotspots = client.paginer("/api/hotspots/search", "hotspots", projectKey=cle_projet)

    donnees = {
        "horodatage": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "commit": (os.environ.get("GITHUB_SHA") or "local")[:12],
        "execution": os.environ.get("GITHUB_RUN_ID", "local"),
        "cle_projet": cle_projet,
        "quality_gate": gate,
        "mesures": mesures,
        "issues": issues,
        "hotspots": hotspots,
    }

    sortie = Path(args.sortie)
    sortie.mkdir(parents=True, exist_ok=True)
    horodatage_fichier = time.strftime("%Y%m%d-%H%M%S", time.gmtime())

    (sortie / f"analyse-{horodatage_fichier}.json").write_text(
        json.dumps(donnees, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (sortie / "RESUME.md").write_text(rendre_markdown(donnees) + "\n", encoding="utf-8")
    ecrire_historique(sortie / "historique.csv", donnees)

    info(f"preuves écrites dans {sortie}")

    statut = gate.get("status", "INCONNU")
    vulnerabilites = mesures.get("vulnerabilities", "?")
    nb_hotspots = mesures.get("security_hotspots", "?")
    info(
        f"quality gate : {statut} · vulnérabilités : {vulnerabilites} · "
        f"security hotspots : {nb_hotspots} · couverture : {mesures.get('coverage', '?')} %"
    )

    resume = os.environ.get("GITHUB_STEP_SUMMARY")
    if resume:
        try:
            with open(resume, "a", encoding="utf-8") as flux:
                flux.write(rendre_markdown(donnees) + "\n")
        except OSError as err:
            avertir(f"écriture du résumé impossible : {err}")

    if statut != "OK":
        if args.sans_gate:
            avertir("quality gate en échec — ignoré (--sans-gate).")
            return 0
        erreur("quality gate en ÉCHEC : le pipeline est interrompu.")
        return 8
    return 0


if __name__ == "__main__":
    sys.exit(main())
