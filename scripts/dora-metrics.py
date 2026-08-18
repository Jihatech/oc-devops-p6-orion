#!/usr/bin/env python3
# =============================================================================
# dora-metrics.py — Calcul des quatre indicateurs DORA depuis l'API GitHub
# =============================================================================
#
# BUT
#   Mesurer les quatre indicateurs DORA de la chaîne CI/CD d'Orion à partir de
#   la source de vérité — l'historique réel des commits, des exécutions de
#   pipeline et des releases — puis les exporter dans des formats exploitables
#   par le rapport de performance, par ELK et par un tableur.
#
#     1. Lead time for changes    délai entre l'écriture d'un commit et sa
#                                 mise en production
#     2. Deployment frequency     fréquence des déploiements
#     3. Change failure rate      part des déploiements qui échouent
#     4. Mean time to restore     délai de retour à un état sain après échec
#
#   Aucune solution gratuite ne couvre correctement ces quatre indicateurs sur
#   GitHub. Un script sur mesure a été retenu pour trois raisons : il est
#   transparent (les définitions retenues sont lisibles et discutables), il est
#   explicable en soutenance, et il ne dépend d'aucun service tiers.
#
# DÉFINITIONS RETENUES — et pourquoi
#   Les indicateurs DORA n'ont de sens que si l'on précise ce qu'on appelle un
#   « déploiement ». Chez Orion, l'application n'est pas encore en production :
#   la convention retenue, et assumée, est la suivante.
#
#   DÉPLOIEMENT = une release publiée par semantic-release sur `main`.
#     C'est le seul événement qui produit un artefact versionné, immuable et
#     promu (images GHCR étiquetées en sémantique). Compter les exécutions de
#     pipeline à la place gonflerait artificiellement la fréquence, puisque
#     toutes ne livrent rien.
#
#   LEAD TIME = médiane des écarts entre la date d'écriture de chaque commit
#     et la publication de la release qui l'embarque.
#     La MÉDIANE et non la moyenne : un unique commit ancien, repris
#     tardivement, décalerait la moyenne sans rien dire du flux réel.
#
#   CHANGE FAILURE RATE = exécutions de pipeline en échec sur `main`, rapportées
#     au total des exécutions sur `main`.
#     Sur `main`, chaque exécution est une tentative de livraison : un échec y
#     est bien un changement qui n'a pas abouti.
#
#   MTTR = médiane des durées entre une exécution en échec sur `main` et la
#     première exécution réussie qui la suit.
#     C'est le délai réel de retour à un état livrable.
#
# FONCTIONNEMENT
#   1. Interroge l'API GitHub (exécutions de workflow, releases, commits) en
#      paginant, sur une fenêtre temporelle paramétrable.
#   2. Calcule les quatre indicateurs selon les définitions ci-dessus.
#   3. Situe chaque valeur sur l'échelle de performance DORA
#      (Elite / High / Medium / Low), ce qui rend le résultat lisible par un
#      lecteur non technique — c'est l'audience du rapport de performance.
#   4. Exporte selon les formats demandés : CSV (tableur et suivi de tendance),
#      JSON (données brutes), Markdown (rapport), NDJSON (ingestion ELK).
#
# PARAMÈTRES
#   -d, --depot <owner/repo>   Dépôt analysé        (défaut : GITHUB_REPOSITORY)
#   -j, --jours <n>            Fenêtre d'analyse    (défaut : 90)
#   -w, --workflow <fichier>   Workflow observé     (défaut : ci.yml)
#   -b, --branche <nom>        Branche de livraison (défaut : main)
#   -s, --sortie <répertoire>  Répertoire de sortie (défaut : docs/captures/dora)
#   -f, --format <csv|json|markdown|elk|tous>   Format ; répétable (défaut : tous)
#   -v, --verbeux              Journalisation détaillée
#
#   Variables d'environnement lues :
#     GITHUB_TOKEN       jeton d'API (recommandé : sans lui, le quota anonyme
#                        de 60 requêtes/heure est vite atteint)
#     GITHUB_REPOSITORY  dépôt par défaut, fourni par GitHub Actions
#
# CONDITIONS D'EXÉCUTION
#   - Python >= 3.8, AUCUNE dépendance externe (bibliothèque standard seule).
#   - Accès réseau à api.github.com.
#   - Jeton en lecture seule : le script n'écrit RIEN sur GitHub.
#   - Le jeton n'est jamais journalisé, ni écrit dans les exports.
#   - Codes de sortie : 0 succès · 1 données insuffisantes · 2 prérequis
#     manquant · 3 paramètre invalide
#
# EXEMPLES
#   GITHUB_TOKEN=xxx python3 scripts/dora-metrics.py --depot Jihatech/oc-devops-p6-orion
#   python3 scripts/dora-metrics.py --jours 30 --format markdown
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

from __future__ import annotations

import argparse
import csv
import json
import os
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

VERBEUX = False
API = "https://api.github.com"

# Seuils publics du rapport « Accelerate State of DevOps ». Ils servent à
# situer un résultat, pas à le juger : le contexte d'Orion (application pas
# encore en production, 2ᵉ sprint) doit accompagner toute lecture.
NIVEAUX = {
    "lead_time": [
        ("Elite", 24, "moins d'un jour"),
        ("High", 24 * 7, "moins d'une semaine"),
        ("Medium", 24 * 30, "moins d'un mois"),
        ("Low", float("inf"), "plus d'un mois"),
    ],
    "mttr": [
        ("Elite", 1, "moins d'une heure"),
        ("High", 24, "moins d'un jour"),
        ("Medium", 24 * 7, "moins d'une semaine"),
        ("Low", float("inf"), "plus d'une semaine"),
    ],
}


def journal(message: str) -> None:
    if VERBEUX:
        print(f"[DEBUG] {message}", file=sys.stderr)


def info(message: str) -> None:
    print(f"[INFO]  {message}", file=sys.stderr)


def avertir(message: str) -> None:
    print(f"[AVERT] {message}", file=sys.stderr)


# -----------------------------------------------------------------------------
# Accès à l'API GitHub
# -----------------------------------------------------------------------------


class ClientGitHub:
    """Client minimal de l'API GitHub (bibliothèque standard uniquement)."""

    def __init__(self, jeton: str | None) -> None:
        self.jeton = jeton

    def _requete(self, url: str) -> list | dict | None:
        requete = urllib.request.Request(url)
        requete.add_header("Accept", "application/vnd.github+json")
        requete.add_header("X-GitHub-Api-Version", "2022-11-28")
        if self.jeton:
            requete.add_header("Authorization", f"Bearer {self.jeton}")
        try:
            with urllib.request.urlopen(requete, timeout=30) as reponse:
                return json.loads(reponse.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            if err.code == 403:
                avertir("HTTP 403 : quota d'API atteint. Fournissez GITHUB_TOKEN.")
            else:
                avertir(f"HTTP {err.code} sur {url.split('/repos/')[-1]}")
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as err:
            avertir(f"API injoignable : {err}")
        return None

    def paginer(self, chemin: str, cle: str | None = None, pages_max: int = 10, **parametres) -> list:
        """Parcourt les pages d'un point d'entrée jusqu'à épuisement."""
        elements: list = []
        for page in range(1, pages_max + 1):
            parametres_page = dict(parametres, per_page=100, page=page)
            url = f"{API}{chemin}?{urllib.parse.urlencode(parametres_page)}"
            donnees = self._requete(url)
            if donnees is None:
                break
            lot = donnees.get(cle, []) if (cle and isinstance(donnees, dict)) else donnees
            if not isinstance(lot, list) or not lot:
                break
            elements.extend(lot)
            journal(f"{chemin} page {page} : {len(lot)} élément(s)")
            if len(lot) < 100:
                break
        return elements


# -----------------------------------------------------------------------------
# Utilitaires temporels
# -----------------------------------------------------------------------------


def date_iso(valeur: str | None) -> datetime | None:
    if not valeur:
        return None
    try:
        return datetime.fromisoformat(valeur.replace("Z", "+00:00"))
    except ValueError:
        return None


def heures_lisibles(heures: float | None) -> str:
    """Formate une durée en heures sous une forme lisible par un non-technicien."""
    if heures is None:
        return "n/d"
    if heures < 1:
        return f"{heures * 60:.0f} min"
    if heures < 48:
        return f"{heures:.1f} h"
    return f"{heures / 24:.1f} j"


def niveau(indicateur: str, valeur: float | None) -> tuple[str, str]:
    if valeur is None:
        return ("n/d", "données insuffisantes")
    for nom, seuil, libelle in NIVEAUX[indicateur]:
        if valeur <= seuil:
            return (nom, libelle)
    return ("Low", "hors échelle")


def niveau_frequence(par_semaine: float) -> tuple[str, str]:
    if par_semaine >= 7:
        return ("Elite", "au moins un déploiement par jour")
    if par_semaine >= 1:
        return ("High", "au moins un déploiement par semaine")
    if par_semaine >= 0.25:
        return ("Medium", "au moins un déploiement par mois")
    return ("Low", "moins d'un déploiement par mois")


def niveau_taux_echec(taux: float) -> tuple[str, str]:
    if taux <= 5:
        return ("Elite", "5 % ou moins")
    if taux <= 10:
        return ("High", "10 % ou moins")
    if taux <= 15:
        return ("Medium", "15 % ou moins")
    return ("Low", "plus de 15 %")


# -----------------------------------------------------------------------------
# Calcul des indicateurs
# -----------------------------------------------------------------------------


def calculer(client: ClientGitHub, depot: str, workflow: str, branche: str, jours: int) -> dict:
    depuis = datetime.now(timezone.utc) - timedelta(days=jours)
    info(f"fenêtre d'analyse : {jours} jours (depuis le {depuis.date()})")

    executions = [
        r for r in client.paginer(
            f"/repos/{depot}/actions/workflows/{workflow}/runs",
            cle="workflow_runs",
            branch=branche,
        )
        if (date_iso(r.get("created_at")) or depuis) >= depuis
    ]
    releases = [
        r for r in client.paginer(f"/repos/{depot}/releases")
        if not r.get("draft") and (date_iso(r.get("published_at")) or depuis) >= depuis
    ]
    commits = [
        c for c in client.paginer(f"/repos/{depot}/commits", sha=branche, since=depuis.isoformat())
    ]

    info(f"{len(executions)} exécution(s), {len(releases)} release(s), {len(commits)} commit(s)")

    resultats: dict = {
        "depot": depot,
        "branche": branche,
        "workflow": workflow,
        "fenetre_jours": jours,
        "calcule_le": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "volumetrie": {
            "executions": len(executions),
            "releases": len(releases),
            "commits": len(commits),
        },
    }

    # --- 1. Deployment frequency -------------------------------------------
    releases_triees = sorted(
        (r for r in releases if date_iso(r.get("published_at"))),
        key=lambda r: date_iso(r["published_at"]),
    )
    # La période de référence court de la PREMIÈRE ACTIVITÉ observée (commit ou
    # release, au plus tôt) jusqu'à maintenant — et non de la première release.
    #
    # Ce choix corrige une aberration constatée au premier calcul : en partant
    # de la première release, publiée deux heures plus tôt, le taux ressortait
    # à 236 déploiements par semaine. Diviser 3 releases par 2 heures produit
    # un nombre exact et dépourvu de sens.
    #
    # Diviser par la fenêtre demandée (90 jours) serait tout aussi trompeur
    # dans l'autre sens, en écrasant un projet de trois jours.
    dates_activite = [d for d in (
        date_iso(releases_triees[0]["published_at"]) if releases_triees else None,
        min((date_iso((c.get("commit", {}).get("author") or {}).get("date"))
             for c in commits
             if date_iso((c.get("commit", {}).get("author") or {}).get("date"))),
            default=None),
    ) if d]

    if releases_triees and dates_activite:
        debut = min(dates_activite)
        duree_jours = max((datetime.now(timezone.utc) - debut).total_seconds() / 86400, 1.0)
        par_semaine = len(releases_triees) / (duree_jours / 7)
    else:
        duree_jours = 0.0
        par_semaine = 0.0

    # En deçà de deux semaines d'observation, un taux hebdomadaire n'a pas de
    # valeur statistique : trop peu d'événements, effets de bord dominants.
    # Le chiffre est publié — masquer une mesure serait pire — mais il est
    # explicitement signalé comme non représentatif.
    fiable = duree_jours >= 14
    nom, libelle = niveau_frequence(par_semaine)
    if not fiable:
        nom = "n/d"
        libelle = f"periode d'observation trop courte ({duree_jours:.1f} j) pour un taux hebdomadaire"

    resultats["deployment_frequency"] = {
        "deploiements": len(releases_triees),
        "periode_jours": round(duree_jours, 2),
        "par_semaine": round(par_semaine, 2),
        "par_jour": round(par_semaine / 7, 2),
        "representatif": fiable,
        "niveau": nom,
        "reference": libelle,
    }

    # --- 2. Lead time for changes ------------------------------------------
    # Chaque commit est rattaché à la PREMIÈRE release publiée après lui :
    # c'est celle qui l'a effectivement livré.
    delais: list[float] = []
    details_lead: list[dict] = []
    for commit in commits:
        ecrit = date_iso(
            (commit.get("commit", {}).get("author") or {}).get("date")
            or (commit.get("commit", {}).get("committer") or {}).get("date")
        )
        if not ecrit:
            continue
        livrant = next(
            (r for r in releases_triees if date_iso(r["published_at"]) >= ecrit), None
        )
        if not livrant:
            continue  # commit pas encore livré : il n'a pas de lead time
        heures = (date_iso(livrant["published_at"]) - ecrit).total_seconds() / 3600
        delais.append(heures)
        details_lead.append({
            "commit": commit.get("sha", "")[:8],
            "message": (commit.get("commit", {}).get("message") or "").split("\n")[0][:70],
            "ecrit_le": ecrit.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "livre_par": livrant.get("tag_name"),
            "heures": round(heures, 2),
        })

    mediane_lead = statistics.median(delais) if delais else None
    nom, libelle = niveau("lead_time", mediane_lead)
    resultats["lead_time"] = {
        "commits_livres": len(delais),
        "commits_non_livres": len(commits) - len(delais),
        "mediane_heures": round(mediane_lead, 2) if mediane_lead is not None else None,
        "moyenne_heures": round(statistics.fmean(delais), 2) if delais else None,
        "min_heures": round(min(delais), 2) if delais else None,
        "max_heures": round(max(delais), 2) if delais else None,
        "niveau": nom,
        "reference": libelle,
        "detail": details_lead[:25],
    }

    # --- 3. Change failure rate --------------------------------------------
    terminees = [r for r in executions if r.get("conclusion") in ("success", "failure")]
    echecs = [r for r in terminees if r["conclusion"] == "failure"]
    taux = (len(echecs) / len(terminees) * 100) if terminees else 0.0
    nom, libelle = niveau_taux_echec(taux)
    resultats["change_failure_rate"] = {
        "executions_terminees": len(terminees),
        "echecs": len(echecs),
        "succes": len(terminees) - len(echecs),
        "taux_pourcent": round(taux, 1),
        "niveau": nom,
        "reference": libelle,
    }

    # --- 4. Mean time to restore -------------------------------------------
    # Parcours chronologique : pour chaque échec, on cherche le premier succès
    # qui le suit. Les échecs consécutifs comptent pour un seul incident, le
    # service restant indisponible tant qu'aucun succès n'est survenu.
    chronologie = sorted(
        (r for r in terminees if date_iso(r.get("created_at"))),
        key=lambda r: date_iso(r["created_at"]),
    )
    restaurations: list[float] = []
    details_mttr: list[dict] = []
    debut_incident = None
    for execution in chronologie:
        instant = date_iso(execution["created_at"])
        if execution["conclusion"] == "failure":
            if debut_incident is None:
                debut_incident = (instant, execution)
        elif debut_incident is not None:
            heures = (instant - debut_incident[0]).total_seconds() / 3600
            restaurations.append(heures)
            details_mttr.append({
                "echec_le": debut_incident[0].strftime("%Y-%m-%dT%H:%M:%SZ"),
                "echec_run": debut_incident[1].get("id"),
                "retabli_le": instant.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "retabli_run": execution.get("id"),
                "heures": round(heures, 2),
            })
            debut_incident = None

    mediane_mttr = statistics.median(restaurations) if restaurations else None
    nom, libelle = niveau("mttr", mediane_mttr)
    resultats["mttr"] = {
        "incidents_resolus": len(restaurations),
        "incident_en_cours": debut_incident is not None,
        "mediane_heures": round(mediane_mttr, 2) if mediane_mttr is not None else None,
        "moyenne_heures": round(statistics.fmean(restaurations), 2) if restaurations else None,
        "max_heures": round(max(restaurations), 2) if restaurations else None,
        "niveau": nom,
        "reference": libelle,
        "detail": details_mttr[:25],
    }

    return resultats


# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------


def exporter_json(resultats: dict, sortie: Path) -> Path:
    fichier = sortie / "dora-metrics.json"
    fichier.write_text(json.dumps(resultats, indent=2, ensure_ascii=False), encoding="utf-8")
    return fichier


def exporter_csv(resultats: dict, sortie: Path) -> Path:
    """Ligne unique ajoutée à un historique : c'est ce fichier qui porte la
    TENDANCE, seule lecture réellement utile de ces indicateurs."""
    fichier = sortie / "historique-dora.csv"
    ligne = {
        "date": resultats["calcule_le"],
        "fenetre_jours": resultats["fenetre_jours"],
        "deploiements": resultats["deployment_frequency"]["deploiements"],
        "deploiements_par_semaine": resultats["deployment_frequency"]["par_semaine"],
        "niveau_frequence": resultats["deployment_frequency"]["niveau"],
        "lead_time_median_h": resultats["lead_time"]["mediane_heures"],
        "niveau_lead_time": resultats["lead_time"]["niveau"],
        "taux_echec_pct": resultats["change_failure_rate"]["taux_pourcent"],
        "niveau_taux_echec": resultats["change_failure_rate"]["niveau"],
        "mttr_median_h": resultats["mttr"]["mediane_heures"],
        "niveau_mttr": resultats["mttr"]["niveau"],
    }
    nouveau = not fichier.exists()
    with open(fichier, "a", encoding="utf-8", newline="") as flux:
        redacteur = csv.DictWriter(flux, fieldnames=list(ligne))
        if nouveau:
            redacteur.writeheader()
        redacteur.writerow(ligne)
    return fichier


def exporter_elk(resultats: dict, sortie: Path) -> Path:
    """NDJSON : un document par ligne, format d'ingestion attendu par
    Elasticsearch (_bulk) et par Filebeat."""
    fichier = sortie / "dora-elk.ndjson"
    horodatage = resultats["calcule_le"]
    documents = []
    for indicateur, valeur, unite in (
        ("deployment_frequency", resultats["deployment_frequency"]["par_semaine"], "par_semaine"),
        ("lead_time", resultats["lead_time"]["mediane_heures"], "heures"),
        ("change_failure_rate", resultats["change_failure_rate"]["taux_pourcent"], "pourcent"),
        ("mttr", resultats["mttr"]["mediane_heures"], "heures"),
    ):
        documents.append({
            "@timestamp": horodatage,
            "service": "microcrm",
            "depot": resultats["depot"],
            "indicateur": indicateur,
            "valeur": valeur,
            "unite": unite,
            "niveau": resultats[indicateur]["niveau"],
        })
    fichier.write_text(
        "\n".join(json.dumps(d, ensure_ascii=False) for d in documents) + "\n",
        encoding="utf-8",
    )
    return fichier


def exporter_markdown(resultats: dict, sortie: Path) -> Path:
    fichier = sortie / "RESUME.md"
    df = resultats["deployment_frequency"]
    lt = resultats["lead_time"]
    cfr = resultats["change_failure_rate"]
    mttr = resultats["mttr"]

    icone = {"Elite": "🟢", "High": "🟢", "Medium": "🟠", "Low": "🔴", "n/d": "⚪"}

    lignes = [
        "# Indicateurs DORA — MicroCRM (Orion)",
        "",
        f"> Calculés le **{resultats['calcule_le']}** sur les **{resultats['fenetre_jours']} derniers jours**,",
        f"> à partir de l'historique réel du dépôt `{resultats['depot']}` (branche `{resultats['branche']}`).",
        f"> Volumétrie analysée : {resultats['volumetrie']['executions']} exécutions de pipeline, "
        f"{resultats['volumetrie']['releases']} releases, {resultats['volumetrie']['commits']} commits.",
        "",
        "## Synthèse",
        "",
        "| Indicateur | Valeur | Niveau DORA | Référence du niveau |",
        "|---|---|---|---|",
        f"| **Fréquence de déploiement** | {df['par_semaine']} / semaine | "
        f"{icone.get(df['niveau'], '')} {df['niveau']} | {df['reference']} |",
        f"| **Délai de livraison** (médiane) | {heures_lisibles(lt['mediane_heures'])} | "
        f"{icone.get(lt['niveau'], '')} {lt['niveau']} | {lt['reference']} |",
        f"| **Taux d'échec des changements** | {cfr['taux_pourcent']} % | "
        f"{icone.get(cfr['niveau'], '')} {cfr['niveau']} | {cfr['reference']} |",
        f"| **Délai de rétablissement** (médiane) | {heures_lisibles(mttr['mediane_heures'])} | "
        f"{icone.get(mttr['niveau'], '')} {mttr['niveau']} | {mttr['reference']} |",
        "",
        "## Détail des calculs",
        "",
        "### Fréquence de déploiement",
        "",
        f"- **{df['deploiements']} déploiements** sur {df['periode_jours']} jours observés",
        f"- soit **{df['par_semaine']} par semaine** ({df['par_jour']} par jour)",
        "",
        "> Un « déploiement » est une **release publiée par semantic-release**, seul événement",
        "> produisant un artefact versionné, immuable et promu. Compter les exécutions de pipeline",
        "> gonflerait la fréquence, puisque toutes ne livrent rien.",
        "",
        "### Délai de livraison (lead time for changes)",
        "",
        f"- **{lt['commits_livres']} commits livrés**, {lt['commits_non_livres']} pas encore livrés",
        f"- médiane **{heures_lisibles(lt['mediane_heures'])}** · moyenne {heures_lisibles(lt['moyenne_heures'])}",
        f"- amplitude : de {heures_lisibles(lt['min_heures'])} à {heures_lisibles(lt['max_heures'])}",
        "",
        "> La **médiane** est retenue plutôt que la moyenne : un commit ancien repris tardivement",
        "> décalerait la moyenne sans rien dire du flux réel.",
        "",
        "### Taux d'échec des changements",
        "",
        f"- **{cfr['echecs']} échecs** sur {cfr['executions_terminees']} exécutions terminées",
        f"- soit **{cfr['taux_pourcent']} %**",
        "",
        "### Délai de rétablissement (MTTR)",
        "",
        f"- **{mttr['incidents_resolus']} incidents** résolus",
        f"- médiane **{heures_lisibles(mttr['mediane_heures'])}** · maximum {heures_lisibles(mttr['max_heures'])}",
        "",
        "> Les échecs consécutifs comptent pour **un seul incident** : la chaîne reste indisponible",
        "> tant qu'aucune exécution n'a réussi.",
        "",
    ]

    if mttr["detail"]:
        lignes += [
            "#### Incidents et rétablissements",
            "",
            "| Échec | Rétablissement | Durée |",
            "|---|---|---|",
        ]
        for incident in mttr["detail"][:10]:
            lignes.append(
                f"| {incident['echec_le']} | {incident['retabli_le']} | "
                f"{heures_lisibles(incident['heures'])} |"
            )
        lignes.append("")

    lignes += [
        "---",
        "",
        "<sub>Généré par `scripts/dora-metrics.py` à partir de l'API GitHub. Les seuils de niveau",
        "proviennent du rapport public « Accelerate State of DevOps » et servent à SITUER un",
        "résultat, non à le juger : ils doivent être lus avec le contexte du projet.</sub>",
    ]

    fichier.write_text("\n".join(lignes) + "\n", encoding="utf-8")
    return fichier


# -----------------------------------------------------------------------------
# Point d'entrée
# -----------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    global VERBEUX
    analyseur = argparse.ArgumentParser(
        prog="dora-metrics.py",
        description="Calcule les quatre indicateurs DORA depuis l'API GitHub.",
    )
    analyseur.add_argument("-d", "--depot", default=os.environ.get("GITHUB_REPOSITORY"))
    analyseur.add_argument("-j", "--jours", type=int, default=90)
    analyseur.add_argument("-w", "--workflow", default="ci.yml")
    analyseur.add_argument("-b", "--branche", default="main")
    analyseur.add_argument("-s", "--sortie", default="docs/captures/dora")
    analyseur.add_argument(
        "-f", "--format", action="append",
        choices=["csv", "json", "markdown", "elk", "tous"],
    )
    analyseur.add_argument("-v", "--verbeux", action="store_true")
    args = analyseur.parse_args(argv if argv is not None else sys.argv[1:])
    VERBEUX = args.verbeux

    if not args.depot:
        print("[ERREUR] dépôt non fourni : utilisez --depot owner/repo.", file=sys.stderr)
        return 3
    if args.jours <= 0:
        print("[ERREUR] --jours doit être strictement positif.", file=sys.stderr)
        return 3

    jeton = os.environ.get("GITHUB_TOKEN")
    if not jeton:
        avertir("GITHUB_TOKEN absent : quota anonyme limité à 60 requêtes/heure.")

    client = ClientGitHub(jeton)
    resultats = calculer(client, args.depot, args.workflow, args.branche, args.jours)

    if resultats["volumetrie"]["executions"] == 0 and resultats["volumetrie"]["releases"] == 0:
        print("[ERREUR] aucune donnée exploitable sur la fenêtre demandée.", file=sys.stderr)
        return 1

    sortie = Path(args.sortie)
    sortie.mkdir(parents=True, exist_ok=True)

    formats = args.format or ["tous"]
    if "tous" in formats:
        formats = ["json", "csv", "markdown", "elk"]

    produits = []
    if "json" in formats:
        produits.append(exporter_json(resultats, sortie))
    if "csv" in formats:
        produits.append(exporter_csv(resultats, sortie))
    if "markdown" in formats:
        produits.append(exporter_markdown(resultats, sortie))
    if "elk" in formats:
        produits.append(exporter_elk(resultats, sortie))

    for fichier in produits:
        info(f"écrit : {fichier}")

    df = resultats["deployment_frequency"]
    lt = resultats["lead_time"]
    cfr = resultats["change_failure_rate"]
    mttr = resultats["mttr"]
    print(
        f"Fréquence {df['par_semaine']}/sem ({df['niveau']}) · "
        f"Lead time {heures_lisibles(lt['mediane_heures'])} ({lt['niveau']}) · "
        f"Taux d'échec {cfr['taux_pourcent']} % ({cfr['niveau']}) · "
        f"MTTR {heures_lisibles(mttr['mediane_heures'])} ({mttr['niveau']})"
    )

    resume = os.environ.get("GITHUB_STEP_SUMMARY")
    if resume and "markdown" in formats:
        try:
            with open(resume, "a", encoding="utf-8") as flux:
                flux.write((sortie / "RESUME.md").read_text(encoding="utf-8") + "\n")
        except OSError as err:
            avertir(f"écriture du résumé impossible : {err}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
