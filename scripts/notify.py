#!/usr/bin/env python3
# =============================================================================
# notify.py — Notification des résultats du pipeline CI/CD
# =============================================================================
#
# BUT
#   Produire et diffuser une synthèse lisible des résultats d'une exécution de
#   pipeline : agrégation des rapports de tests et de couverture, rédaction
#   d'un résumé Markdown affiché directement dans l'interface GitHub Actions,
#   et ouverture (ou mise à jour) d'une issue de suivi en cas d'échec.
#
#   Répond à l'exigence de livrable « script de notification des résultats de
#   pipeline », et à la faiblesse f9 de l'audit : aujourd'hui, la communication
#   Dev↔Ops passe par e-mail et par oral, sans historique ni traçabilité. Une
#   issue automatique transforme un échec en objet suivi, assigné et daté.
#
# FONCTIONNEMENT
#   1. Analyse les rapports présents dans le répertoire indiqué (--rapports) :
#      - fichiers JUnit XML  -> nombre de tests, échecs, erreurs, ignorés
#      - fichiers LCOV       -> taux de couverture de lignes du frontend
#      - jacoco.xml          -> taux de couverture d'instructions du backend
#      Chaque analyse est tolérante aux fichiers absents ou malformés : la
#      notification ne doit JAMAIS faire échouer un pipeline par elle-même.
#   2. Compose un rapport Markdown (tableau de synthèse + détail par composant
#      + lien vers l'exécution).
#   3. Diffuse selon les canaux demandés (--canal, répétable) :
#      - « resume »  : écrit dans $GITHUB_STEP_SUMMARY (visible dans l'onglet
#                      Actions, sans quitter l'interface)
#      - « console » : écrit sur la sortie standard
#      - « issue »   : crée ou met à jour une issue GitHub étiquetée
#                      « ci-echec » (uniquement si le statut est « echec »)
#      - « fichier » : écrit dans le fichier indiqué par --fichier
#   4. Sort toujours en code 0 sauf erreur d'usage : un défaut de notification
#      ne doit pas masquer ni inverser le verdict réel du pipeline.
#
# PARAMÈTRES
#   -s, --statut <succes|echec|instable>  Statut global du pipeline (requis)
#   -r, --rapports <répertoire>   Répertoire des rapports         (défaut : reports)
#   -c, --canal <resume|console|issue|fichier>
#                                 Canal de diffusion ; répétable  (défaut : resume+console)
#   -f, --fichier <chemin>        Fichier de sortie du canal « fichier »
#   -t, --titre <texte>           Titre du rapport                (défaut : « Résultats du pipeline »)
#   -n, --simulation              N'écrit rien et n'appelle aucune API :
#                                 affiche ce qui serait fait
#   -v, --verbeux                 Journalisation détaillée
#
#   Variables d'environnement lues (fournies par GitHub Actions) :
#     GITHUB_STEP_SUMMARY   fichier de résumé du job (canal « resume »)
#     GITHUB_TOKEN          jeton d'API, requis par le canal « issue »
#     GITHUB_REPOSITORY     « proprietaire/depot »
#     GITHUB_RUN_ID         identifiant de l'exécution (lien direct)
#     GITHUB_SHA            commit analysé
#     GITHUB_REF_NAME       branche ou tag
#     GITHUB_SERVER_URL     URL de l'instance    (défaut : https://github.com)
#
# CONDITIONS D'EXÉCUTION
#   - Python >= 3.8. AUCUNE dépendance externe (bibliothèque standard
#     uniquement) : le script s'exécute sur n'importe quel runner sans étape
#     d'installation préalable, et reste utilisable hors CI.
#   - Le canal « issue » exige GITHUB_TOKEN avec la permission `issues: write`
#     et un accès réseau. En son absence, le canal est ignoré avec un
#     avertissement — sans échec.
#   - Le jeton n'est JAMAIS journalisé ni affiché, même en mode verbeux.
#   - Codes de sortie : 0 succès (y compris notification partielle)
#     · 3 paramètre invalide
#
# EXEMPLES
#   python scripts/notify.py --statut succes
#   python scripts/notify.py -s echec -c resume -c issue -r reports
#   python scripts/notify.py -s succes -c fichier -f rapport.md --simulation
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

STATUTS = {
    "succes": ("✅", "Succès"),
    "echec": ("❌", "Échec"),
    "instable": ("⚠️", "Instable"),
}

CANAUX = ("resume", "console", "issue", "fichier")
ETIQUETTE_ISSUE = "ci-echec"

VERBEUX = False


def journal(message: str) -> None:
    """Écrit un message de diagnostic sur stderr (jamais sur stdout, qui porte
    le rapport lui-même et peut être redirigé)."""
    if VERBEUX:
        print(f"[DEBUG] {message}", file=sys.stderr)


def avertir(message: str) -> None:
    print(f"[AVERT] {message}", file=sys.stderr)


# -----------------------------------------------------------------------------
# Collecte des résultats
# -----------------------------------------------------------------------------


@dataclass
class ResultatTests:
    """Agrégat des résultats de tests d'un composant."""

    total: int = 0
    echecs: int = 0
    erreurs: int = 0
    ignores: int = 0
    fichiers: int = 0

    @property
    def reussis(self) -> int:
        return max(0, self.total - self.echecs - self.erreurs - self.ignores)

    @property
    def ok(self) -> bool:
        return self.echecs == 0 and self.erreurs == 0

    @property
    def taux_reussite(self) -> float:
        return (self.reussis / self.total * 100) if self.total else 0.0


@dataclass
class Rapport:
    """Synthèse complète d'une exécution de pipeline."""

    statut: str
    titre: str
    tests: ResultatTests = field(default_factory=ResultatTests)
    couverture: dict[str, float] = field(default_factory=dict)
    contexte: dict[str, str] = field(default_factory=dict)


def analyser_junit(repertoire: Path) -> ResultatTests:
    """Agrège tous les fichiers JUnit XML trouvés récursivement.

    Tolérant par conception : un fichier illisible est signalé puis ignoré.
    """
    resultat = ResultatTests()
    if not repertoire.is_dir():
        journal(f"répertoire de rapports absent : {repertoire}")
        return resultat

    for fichier in sorted(repertoire.rglob("*.xml")):
        if "jacoco" in fichier.name.lower():
            continue
        try:
            racine = ET.parse(fichier).getroot()
        except (ET.ParseError, OSError) as err:
            journal(f"XML ignoré ({fichier.name}) : {err}")
            continue

        suites = [racine] if racine.tag == "testsuite" else racine.iter("testsuite")
        compte = False
        for suite in suites:
            if suite.get("tests") is None:
                continue
            compte = True
            resultat.total += int(suite.get("tests", 0) or 0)
            resultat.echecs += int(suite.get("failures", 0) or 0)
            resultat.erreurs += int(suite.get("errors", 0) or 0)
            resultat.ignores += int(suite.get("skipped", 0) or 0)
        if compte:
            resultat.fichiers += 1

    journal(f"JUnit : {resultat.total} tests sur {resultat.fichiers} fichier(s)")
    return resultat


def analyser_lcov(fichier: Path) -> float | None:
    """Calcule le taux de couverture de lignes depuis un rapport LCOV.

    LCOV agrège par fichier source : LF = lignes instrumentées,
    LH = lignes couvertes. Le taux global est la somme des LH sur la somme
    des LF (et non la moyenne des taux, qui surpondérerait les petits fichiers).
    """
    if not fichier.is_file():
        return None
    total = couvert = 0
    try:
        for ligne in fichier.read_text(encoding="utf-8", errors="replace").splitlines():
            if ligne.startswith("LF:"):
                total += int(ligne[3:] or 0)
            elif ligne.startswith("LH:"):
                couvert += int(ligne[3:] or 0)
    except (OSError, ValueError) as err:
        avertir(f"LCOV illisible ({fichier}) : {err}")
        return None
    return (couvert / total * 100) if total else None


def analyser_jacoco(fichier: Path) -> float | None:
    """Extrait le taux de couverture d'instructions depuis un rapport JaCoCo XML."""
    if not fichier.is_file():
        return None
    try:
        racine = ET.parse(fichier).getroot()
    except (ET.ParseError, OSError) as err:
        avertir(f"JaCoCo illisible ({fichier}) : {err}")
        return None

    # Seuls les compteurs de premier niveau décrivent le projet entier.
    for compteur in racine.findall("counter"):
        if compteur.get("type") == "INSTRUCTION":
            couvert = int(compteur.get("covered", 0) or 0)
            manque = int(compteur.get("missed", 0) or 0)
            total = couvert + manque
            return (couvert / total * 100) if total else None
    return None


def collecter(repertoire: Path, statut: str, titre: str) -> Rapport:
    rapport = Rapport(statut=statut, titre=titre)
    rapport.tests = analyser_junit(repertoire)

    taux_front = analyser_lcov(repertoire / "front" / "lcov.info")
    if taux_front is not None:
        rapport.couverture["Frontend (lignes)"] = taux_front

    taux_back = analyser_jacoco(repertoire / "back" / "jacoco.xml")
    if taux_back is not None:
        rapport.couverture["Backend (instructions)"] = taux_back

    for cle, variable in (
        ("Dépôt", "GITHUB_REPOSITORY"),
        ("Branche", "GITHUB_REF_NAME"),
        ("Commit", "GITHUB_SHA"),
        ("Exécution", "GITHUB_RUN_ID"),
    ):
        valeur = os.environ.get(variable)
        if valeur:
            rapport.contexte[cle] = valeur[:12] if variable == "GITHUB_SHA" else valeur

    return rapport


# -----------------------------------------------------------------------------
# Rendu Markdown
# -----------------------------------------------------------------------------


def url_execution() -> str | None:
    serveur = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    depot = os.environ.get("GITHUB_REPOSITORY")
    run = os.environ.get("GITHUB_RUN_ID")
    return f"{serveur}/{depot}/actions/runs/{run}" if depot and run else None


def rendre_markdown(rapport: Rapport) -> str:
    icone, libelle = STATUTS[rapport.statut]
    lignes: list[str] = [f"## {icone} {rapport.titre} — {libelle}", ""]

    if rapport.contexte:
        lignes += ["| Contexte | Valeur |", "|---|---|"]
        lignes += [f"| {cle} | `{valeur}` |" for cle, valeur in rapport.contexte.items()]
        lignes.append("")

    tests = rapport.tests
    if tests.total:
        etat = "✅" if tests.ok else "❌"
        lignes += [
            "### Tests automatisés",
            "",
            "| Indicateur | Valeur |",
            "|---|---|",
            f"| Total exécutés | **{tests.total}** |",
            f"| Réussis | {tests.reussis} |",
            f"| Échecs | {tests.echecs} |",
            f"| Erreurs | {tests.erreurs} |",
            f"| Ignorés | {tests.ignores} |",
            f"| Taux de réussite | {etat} **{tests.taux_reussite:.1f} %** |",
            "",
        ]
    else:
        lignes += ["### Tests automatisés", "", "_Aucun rapport de test exploitable._", ""]

    if rapport.couverture:
        lignes += ["### Couverture de code", "", "| Composant | Couverture |", "|---|---|"]
        for composant, taux in rapport.couverture.items():
            # Seuil de 60 % retenu dans docs/03 (§5.1), adapté au niveau
            # déclaré de l'équipe sur JUnit.
            marque = "✅" if taux >= 60 else "⚠️"
            lignes.append(f"| {composant} | {marque} {taux:.1f} % |")
        lignes.append("")

    lien = url_execution()
    if lien:
        lignes += [f"[Consulter l'exécution complète]({lien})", ""]

    lignes.append("<sub>Généré par `scripts/notify.py` — Projet 6 Orion</sub>")
    return "\n".join(lignes)


# -----------------------------------------------------------------------------
# Canaux de diffusion
# -----------------------------------------------------------------------------


def diffuser_resume(contenu: str, simulation: bool) -> None:
    chemin = os.environ.get("GITHUB_STEP_SUMMARY")
    if not chemin:
        avertir("GITHUB_STEP_SUMMARY non défini : canal « resume » ignoré (hors CI).")
        return
    if simulation:
        print(f"[SIMULATION] écriture du résumé dans {chemin}", file=sys.stderr)
        return
    try:
        with open(chemin, "a", encoding="utf-8") as flux:
            flux.write(contenu + "\n")
        journal(f"résumé écrit dans {chemin}")
    except OSError as err:
        avertir(f"écriture du résumé impossible : {err}")


def diffuser_fichier(contenu: str, chemin: str | None, simulation: bool) -> None:
    if not chemin:
        avertir("canal « fichier » demandé sans --fichier : ignoré.")
        return
    if simulation:
        print(f"[SIMULATION] écriture dans {chemin}", file=sys.stderr)
        return
    try:
        cible = Path(chemin)
        cible.parent.mkdir(parents=True, exist_ok=True)
        cible.write_text(contenu + "\n", encoding="utf-8")
        journal(f"rapport écrit dans {chemin}")
    except OSError as err:
        avertir(f"écriture du fichier impossible : {err}")


def appeler_api(url: str, jeton: str, methode: str = "GET", corps: dict | None = None) -> dict | list | None:
    """Appel minimal à l'API GitHub via la bibliothèque standard.

    Aucune dépendance externe n'est ajoutée au projet pour cette seule fonction.
    Le jeton n'est jamais journalisé.
    """
    donnees = json.dumps(corps).encode("utf-8") if corps is not None else None
    requete = urllib.request.Request(url, data=donnees, method=methode)
    requete.add_header("Authorization", f"Bearer {jeton}")
    requete.add_header("Accept", "application/vnd.github+json")
    requete.add_header("X-GitHub-Api-Version", "2022-11-28")
    requete.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(requete, timeout=20) as reponse:
            return json.loads(reponse.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        avertir(f"API GitHub {methode} {url.split('/repos/')[-1]} : HTTP {err.code}")
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as err:
        avertir(f"API GitHub injoignable : {err}")
    return None


def diffuser_issue(contenu: str, rapport: Rapport, simulation: bool) -> None:
    """Ouvre une issue de suivi en cas d'échec, ou commente celle déjà ouverte.

    Une seule issue reste ouverte à la fois par branche : les échecs successifs
    y sont ajoutés en commentaire plutôt que de créer un doublon à chaque
    exécution — sans quoi le canal deviendrait un générateur de bruit.
    """
    if rapport.statut != "echec":
        journal("statut non « echec » : aucune issue à ouvrir.")
        return

    jeton = os.environ.get("GITHUB_TOKEN")
    depot = os.environ.get("GITHUB_REPOSITORY")
    if not jeton or not depot:
        avertir("GITHUB_TOKEN ou GITHUB_REPOSITORY absent : canal « issue » ignoré.")
        return

    branche = os.environ.get("GITHUB_REF_NAME", "inconnue")
    titre = f"[CI] Échec du pipeline sur « {branche} »"

    if simulation:
        print(f"[SIMULATION] issue « {titre} » sur {depot}", file=sys.stderr)
        return

    base = f"https://api.github.com/repos/{depot}/issues"
    existantes = appeler_api(f"{base}?state=open&labels={ETIQUETTE_ISSUE}", jeton)

    if isinstance(existantes, list):
        for issue in existantes:
            if issue.get("title") == titre:
                numero = issue.get("number")
                appeler_api(f"{base}/{numero}/comments", jeton, "POST", {"body": contenu})
                print(f"[OK] échec ajouté à l'issue #{numero}", file=sys.stderr)
                return

    creee = appeler_api(base, jeton, "POST", {"title": titre, "body": contenu, "labels": [ETIQUETTE_ISSUE]})
    if isinstance(creee, dict) and creee.get("number"):
        print(f"[OK] issue #{creee['number']} ouverte", file=sys.stderr)


# -----------------------------------------------------------------------------
# Point d'entrée
# -----------------------------------------------------------------------------


def analyser_arguments(argv: list[str]) -> argparse.Namespace:
    analyseur = argparse.ArgumentParser(
        prog="notify.py",
        description="Notification des résultats du pipeline CI/CD d'Orion.",
        epilog="Voir l'en-tête du fichier pour la documentation complète.",
    )
    analyseur.add_argument("-s", "--statut", required=True, choices=sorted(STATUTS))
    analyseur.add_argument("-r", "--rapports", default="reports")
    analyseur.add_argument("-c", "--canal", action="append", choices=CANAUX)
    analyseur.add_argument("-f", "--fichier")
    analyseur.add_argument("-t", "--titre", default="Résultats du pipeline")
    analyseur.add_argument("-n", "--simulation", action="store_true")
    analyseur.add_argument("-v", "--verbeux", action="store_true")
    return analyseur.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    global VERBEUX
    args = analyser_arguments(argv if argv is not None else sys.argv[1:])
    VERBEUX = args.verbeux

    canaux = args.canal or ["resume", "console"]
    journal(f"canaux : {', '.join(canaux)}")

    rapport = collecter(Path(args.rapports), args.statut, args.titre)
    contenu = rendre_markdown(rapport)

    if "console" in canaux:
        print(contenu)
    if "resume" in canaux:
        diffuser_resume(contenu, args.simulation)
    if "fichier" in canaux:
        diffuser_fichier(contenu, args.fichier, args.simulation)
    if "issue" in canaux:
        diffuser_issue(contenu, rapport, args.simulation)

    # Le script ne porte pas le verdict du pipeline : il le rapporte.
    return 0


if __name__ == "__main__":
    sys.exit(main())
