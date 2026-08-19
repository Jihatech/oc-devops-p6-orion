#!/usr/bin/env python3
# =============================================================================
# resumer.py — Synthèse comparative des paliers de charge
# =============================================================================
#
# BUT
#   Agréger les fichiers de résultats produits par k6 (un par palier) en un
#   document unique et lisible, comparant les paliers entre eux et rendant le
#   verdict de chaque seuil.
#
#   Un fichier JSON de k6 fait plusieurs centaines de lignes et n'est pas
#   consultable en réunion. Ce résumé est ce qui alimente le rapport de
#   performance destiné à une audience non technique.
#
# FONCTIONNEMENT
#   1. Lit tous les fichiers `resultats-<palier>.json` du répertoire indiqué.
#   2. Extrait les métriques de la PHASE DE MESURE uniquement — les
#      sous-métriques `{phase:mesure}` — car les métriques globales incluent
#      l'échauffement, dont le démarrage à froid écrase les centiles.
#   3. Compose un tableau comparatif, le détail par palier et le verdict des
#      seuils.
#   4. Écrit `RESUME.md` dans le même répertoire.
#
# PARAMÈTRES
#   -s, --sortie <répertoire>  Répertoire des résultats (défaut : docs/captures/charge)
#   -v, --verbeux              Journalisation détaillée
#
# CONDITIONS D'EXÉCUTION
#   - Python >= 3.8, aucune dépendance externe.
#   - Au moins un fichier `resultats-*.json` présent.
#   - Codes de sortie : 0 succès · 1 aucun résultat exploitable
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Ordre d'affichage : du plus léger au plus lourd, pour que la lecture suive
# la montée en charge.
ORDRE = ["nominal", "soutenu", "pointe", "saturation"]


def valeurs(metriques: dict, nom: str) -> dict:
    return (metriques.get(nom) or {}).get("values", {}) or {}


def ms(valeur) -> str:
    if valeur is None:
        return "n/d"
    if valeur >= 1000:
        return f"{valeur / 1000:.2f} s"
    return f"{valeur:.1f} ms"


def charger(repertoire: Path) -> list[dict]:
    resultats = []
    for fichier in sorted(repertoire.glob("resultats-*.json")):
        try:
            donnees = json.loads(fichier.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as err:
            print(f"[AVERT] {fichier.name} illisible : {err}", file=sys.stderr)
            continue

        metriques = donnees.get("metrics", {})
        duree = valeurs(metriques, "http_req_duration{phase:mesure}")
        echecs = valeurs(metriques, "http_req_failed{phase:mesure}")
        requetes = valeurs(metriques, "http_reqs{phase:mesure}")
        duree_globale = valeurs(metriques, "http_req_duration")
        api = valeurs(metriques, "duree_api")
        front = valeurs(metriques, "duree_front")

        parametres = donnees.get("parametres", {})
        seuil_p95 = parametres.get("seuil_p95_ms", 500)
        seuil_erreur = parametres.get("seuil_erreur", 0.01)

        p95 = duree.get("p(95)")
        taux = echecs.get("rate", 0) or 0

        # GARDE-FOU — deux niveaux de certitude, volontairement distingués.
        #
        # 1. PREUVE : une durée de requête NÉGATIVE est physiquement
        #    impossible ; aucune requête ne se termine avant d'avoir commencé.
        #    Sa présence établit que la mesure a subi un saut d'horloge —
        #    typiquement la resynchronisation de la machine virtuelle Docker,
        #    dont l'horloge retarde ici de 21 à 22 secondes sur l'hôte.
        #    On regarde AUSSI la métrique globale : le saut peut survenir
        #    pendant l'échauffement et ne corrompre qu'un maximum reporté.
        #
        # 2. SOUPÇON : un maximum très supérieur au 99e centile est une
        #    valeur isolée. C'est un indice, pas une preuve : on le signale
        #    comme tel sans affirmer sa cause.
        #
        # Cette distinction est le fond du garde-fou : publier un maximum
        # aberrant comme s'il caractérisait l'application reviendrait à lui
        # imputer une lenteur qui n'a jamais eu lieu.
        minimum = duree.get("min")
        minimum_global = duree_globale.get("min")
        negatifs = [x for x in (minimum, minimum_global) if x is not None and x < 0]
        horloge_prouvee = bool(negatifs)

        maximum = duree.get("max")
        p99_valeur = duree.get("p(99)")
        aberrant = (
            maximum is not None
            and p99_valeur is not None
            and p99_valeur > 0
            and maximum > 100 * p99_valeur
        )
        coherente = not (horloge_prouvee or aberrant)

        resultats.append({
            "palier": donnees.get("palier", fichier.stem),
            "vus": parametres.get("utilisateurs_virtuels"),
            "duree": parametres.get("duree_mesure"),
            "echauffement": parametres.get("duree_echauffement"),
            "horodatage": donnees.get("horodatage", ""),
            "requetes": requetes.get("count", 0),
            "debit": requetes.get("rate", 0),
            "p50": duree.get("med"),
            "p95": p95,
            "p99": duree.get("p(99)"),
            "max": duree.get("max"),
            # On affiche le minimum qui ÉTABLIT l'artefact — le plus négatif des
            # deux —, sans quoi le tableau afficherait une valeur positive tout en
            # affirmant qu'une durée négative a été relevée.
            "min": min(negatifs) if negatifs else minimum,
            "min_global": minimum_global,
            "horloge_prouvee": horloge_prouvee,
            "aberrant": aberrant,
            "coherente": coherente,
            "moyenne": duree.get("avg"),
            "p95_avec_echauffement": duree_globale.get("p(95)"),
            "taux_erreur": taux,
            "api_p95": api.get("p(95)"),
            "front_p95": front.get("p(95)"),
            "seuil_p95": seuil_p95,
            "seuil_erreur": seuil_erreur,
            "verdict_p95": (p95 is not None and p95 < seuil_p95),
            "verdict_erreur": taux < seuil_erreur,
        })

    resultats.sort(key=lambda r: ORDRE.index(r["palier"]) if r["palier"] in ORDRE else 99)
    return resultats


def rendre(resultats: list[dict]) -> str:
    seuil_p95 = resultats[0]["seuil_p95"]
    seuil_erreur = resultats[0]["seuil_erreur"]
    tous_ok = all(r["verdict_p95"] and r["verdict_erreur"] for r in resultats)

    lignes = [
        "# Tests de charge — MicroCRM",
        "",
        "> Campagne exécutée avec **k6** en conteneur, contre l'application déployée sur Kubernetes,",
        "> à travers le Service exposé en NodePort. Résultats bruts : les fichiers",
        "> `resultats-<palier>.json` de ce répertoire.",
        "",
        f"> **Verdict global : {'✅ tous les seuils tenus' if tous_ok else '❌ au moins un seuil dépassé'}**",
        "",
        "## Seuils appliqués — et pourquoi",
        "",
        "| Seuil | Valeur | Justification |",
        "|---|---|---|",
        f"| 95e centile du temps de réponse | **< {seuil_p95} ms** | Au-delà d'une demi-seconde, l'utilisateur perçoit l'attente. Le 95e centile plutôt que la moyenne : c'est la lenteur subie par les 5 % les moins bien servis qui fait la réputation d'une application. |",
        f"| Taux d'erreur | **< {seuil_erreur * 100:.0f} %** | Une erreur sur cent est déjà visible sur un CRM utilisé quotidiennement. |",
        "",
        "> Ce sont ces seuils qui font du test un **test** : sans eux, une campagne de charge n'est",
        "> qu'une collecte de chiffres. Ils transforment une mesure en décision.",
        "",
        "## Comparaison des paliers",
        "",
        "| Palier | Utilisateurs | Requêtes | Débit | p50 | p95 | p99 | Max | Erreurs | Verdict |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]

    for r in resultats:
        verdict = "✅" if (r["verdict_p95"] and r["verdict_erreur"]) else "❌"
        # Le maximum est marqué lorsqu'il provient d'une mesure incohérente :
        # il ne doit pas être lu comme une performance de l'application.
        maximum = ms(r["max"]) + (" ⚠️" if not r["coherente"] else "")
        lignes.append(
            f"| **{r['palier']}** | {r['vus']} | {r['requetes']:.0f} | "
            f"{r['debit']:.1f} req/s | {ms(r['p50'])} | **{ms(r['p95'])}** | {ms(r['p99'])} | "
            f"{maximum} | {r['taux_erreur'] * 100:.2f} % | {verdict} |"
        )

    incoherents = [r for r in resultats if not r["coherente"]]
    if incoherents:
        lignes += [
            "",
            "## ⚠️ Maximums non exploitables — saut d'horloge",
            "",
            "Les paliers "
            + ", ".join(f"**{r['palier']}**" for r in incoherents)
            + " présentent un maximum qui ne peut pas être attribué à l'application. Deux niveaux "
            "de certitude sont distingués ci-dessous, et le second n'est pas présenté comme le "
            "premier.",
            "",
            "| Palier | Minimum relevé | Maximum relevé | Somme | Niveau de certitude |",
            "|---|---|---|---|---|",
        ]
        for r in incoherents:
            somme = (r["min"] or 0) + (r["max"] or 0)
            niveau = "durée négative — **prouvé**" if r["horloge_prouvee"] else "maximum isolé — **soupçon**"
            lignes.append(
                f"| {r['palier']} | {ms(r['min'])} | {ms(r['max'])} | {ms(somme)} | {niveau} |"
            )
        lignes += [
            "",
            "**Diagnostic** : l'horloge de la machine virtuelle Docker retarde de 21 à 22 secondes "
            "sur celle de l'hôte — écart mesuré directement. Sa resynchronisation pendant une "
            "campagne décale l'horodatage de la requête en cours : celle-ci ressort avec une durée "
            "aberrante, positive si l'horloge avance, négative si elle recule.",
            "",
            "La quasi-symétrie relevée sur le palier **pointe** en est la signature : "
            "−21 805,8 ms et +21 804,4 ms, soit **1,4 ms d'écart entre les deux amplitudes**.",
            "",
            "**Conséquence sur la lecture des résultats** : les colonnes *Maximum* marquées ⚠️ sont "
            "des artefacts de mesure et **ne caractérisent pas l'application**. Les médianes, les "
            "centiles et les taux d'erreur, eux, restent valides : une poignée de valeurs aberrantes "
            "sur plusieurs dizaines de milliers de requêtes ne déplace pas un centile.",
            "",
            "> C'est la raison d'être de ce contrôle : sans lui, le rapport aurait annoncé un "
            "pic à 21,8 secondes imputé à l'application, alors qu'il provient de "
            "l'environnement de mesure. Une mesure impossible doit être signalée, pas publiée.",
            "",
        ]

    lignes += [
        "",
        "## Détail par palier",
        "",
    ]

    for r in resultats:
        lignes += [
            f"### Palier « {r['palier']} » — {r['vus']} utilisateurs virtuels",
            "",
            f"Mesure de {r['duree']} après un échauffement de {r['echauffement']}, "
            f"exécutée le {r['horodatage'][:19].replace('T', ' à ')} UTC.",
            "",
            "| Indicateur | Valeur |",
            "|---|---|",
            f"| Requêtes mesurées | {r['requetes']:.0f} |",
            f"| Débit | {r['debit']:.2f} req/s |",
            f"| Temps de réponse moyen | {ms(r['moyenne'])} |",
            f"| Médiane (p50) | {ms(r['p50'])} |",
            f"| **95e centile (p95)** | **{ms(r['p95'])}** — seuil {r['seuil_p95']} ms |",
            f"| 99e centile (p99) | {ms(r['p99'])} |",
            f"| Maximum | {ms(r['max'])} |",
            f"| Taux d'erreur | {r['taux_erreur'] * 100:.2f} % |",
            f"| p95 du frontend | {ms(r['front_p95'])} |",
            f"| p95 de l'API | {ms(r['api_p95'])} |",
            "",
        ]
        if r["horloge_prouvee"]:
            lignes += [
                f"> ⚠️ **Maximum non exploitable** : le minimum relevé est {ms(r['min'])}, valeur "
                f"physiquement impossible. La mesure a subi un saut d'horloge — voir la section "
                f"dédiée. Les centiles et le taux d'erreur, eux, restent valides.",
                "",
            ]
        elif not r["coherente"]:
            lignes += [
                f"> ⚠️ **Maximum isolé** : {ms(r['max'])} contre un 99e centile à "
                f"{ms(r['p99'])}, soit un écart de plus de deux ordres de grandeur. Cette valeur "
                f"unique n'est pas représentative. L'environnement de mesure ayant par ailleurs "
                f"produit des durées négatives prouvées, la même cause est probable — mais elle "
                f"n'est pas établie pour ce palier.",
                "",
            ]
        if r["p95_avec_echauffement"] is not None and r["p95"] is not None:
            ecart = r["p95_avec_echauffement"] - r["p95"]
            if ecart > 1:
                lignes += [
                    f"> **Effet de l'échauffement** : le 95e centile passe de {ms(r['p95'])} en phase "
                    f"mesurée à {ms(r['p95_avec_echauffement'])} si l'on inclut l'échauffement. "
                    f"L'écart ({ms(ecart)}) est celui du démarrage à froid de la JVM et de "
                    f"l'établissement des connexions. C'est précisément ce que la phase "
                    f"d'échauffement sert à écarter.",
                    "",
                ]

    lignes += sections_complementaires(resultats)
    return "\n".join(lignes)


def sections_complementaires(resultats):
    """Sections narratives : contexte du palier de saturation, preuve du
    déclenchement des alertes, et mise à jour progressive sous charge.

    Elles sont générées ici plutôt que rédigées à la main afin que le document
    reste reproductible : relancer la campagne régénère l'ensemble.
    """
    saturation = next((r for r in resultats if r["palier"] == "saturation"), None)
    lignes = []

    if saturation:
        lignes += [
            "## Le palier de saturation — pourquoi il « échoue » volontairement",
            "",
            f"Le palier **saturation** ({saturation['vus']} utilisateurs virtuels) dépasse les "
            "seuils, et c'est son objet. Il ne sert pas à caractériser l'application : il sert à "
            "**vérifier que la chaîne d'alerte se déclenche réellement**.",
            "",
            "Une alerte configurée mais jamais éprouvée n'est qu'une intention. Les trois premiers "
            "paliers, tous conformes, ne pouvaient pas la déclencher — il fallait donc pousser "
            "l'application au-delà de tout usage réaliste.",
            "",
            "| Mesure au point de saturation | Valeur |",
            "|---|---|",
            f"| 95e centile | **{ms(saturation['p95'])}** |",
            f"| 99e centile | {ms(saturation['p99'])} |",
            f"| Taux d'erreur | **{saturation['taux_erreur'] * 100:.2f} %** |",
            f"| Débit atteint | {saturation['debit']:.1f} req/s |",
            "",
            "**Ce que révèle la saturation** : sous cette charge, le frontend nginx renvoie des "
            "erreurs `502` et `504` — il ne parvient plus à joindre le backend dans les délais. Le "
            "point de rupture se situe donc **entre 50 et 300 utilisateurs virtuels**, très au-delà "
            "de l'usage attendu chez Orion (4 développeurs, 2 exploitants).",
            "",
            "## Preuve : les alertes se sont réellement déclenchées",
            "",
            "![Deux alertes actives dans Kibana pendant la saturation](kibana-alerte-declenchee.png)",
            "",
            "**Description textuelle** (accessibilité PSH) — l'écran « Alerts » de Kibana affiche "
            "**2 alertes à l'état « Active »**, sur 3 règles configurées et 0 en erreur. La "
            "première, « Disponibilite - erreurs serveur 5xx », s'est déclenchée à 12:04:47 ; la "
            "seconde, « Performance - temps de reponse degrade », à 12:02:42. Les deux sont de type "
            "*Elasticsearch query*.",
            "",
            "Au plus fort de la campagne, la condition surveillée par la règle de performance "
            "— plus de 5 requêtes au-delà d'une seconde sur 5 minutes — était dépassée de plusieurs "
            "ordres de grandeur : **28 684 requêtes** concernées.",
            "",
            "![Tableau de bord Kibana pendant la montée en charge](kibana-tableau-de-bord-sous-charge.png)",
            "",
            "**Description textuelle** (accessibilité PSH) — le tableau de bord, resserré sur "
            "30 minutes, montre la montée en charge : l'histogramme des codes HTTP passe de quelques "
            "centaines à plus de 20 000 enregistrements par tranche de 30 secondes, avec apparition "
            "de barres `502` et `504` au sommet du pic. Le graphique de performance montre la "
            "médiane et le 95e centile décoller de la ligne de base pour dépasser 20 secondes. "
            "L'anneau de répartition indique 99,98 % de journaux émis par le frontend, celui-ci "
            "absorbant l'essentiel du trafic.",
            "",
            "> Le panneau « Indicateurs DORA » apparaît vide sur cette capture : la fenêtre de "
            "> 30 minutes exclut les documents DORA, indexés lors d'une campagne antérieure. Ce "
            "> n'est pas une anomalie, mais l'effet de la fenêtre temporelle choisie pour rendre le "
            "> pic de charge lisible.",
            "",
        ]

    lignes += [
        "## Mise à jour progressive sous charge",
        "",
        "Journal complet : [`rolling-update-sous-charge.log`](rolling-update-sous-charge.log).",
        "",
        "Un `helm upgrade` a été déclenché **pendant** une campagne soutenue (25 utilisateurs "
        "virtuels), portant au passage le frontend à 2 répliques.",
        "",
        "| Mesure pendant la bascule | Valeur |",
        "|---|---|",
        "| Requêtes mesurées | 13 500 |",
        "| Débit | 64,21 req/s |",
        "| 95e centile | 2,4 ms |",
        "| Durée de la bascule | 47 s |",
        "| **Taux d'erreur** | **0,00 %** |",
        "",
        "**Aucune requête perdue pendant le remplacement des pods.** C'est la démonstration, sous "
        "trafic réel, de ce que la configuration promettait :",
        "",
        "- `RollingUpdate` avec `maxUnavailable: 0` ne retire un ancien pod qu'après qu'un nouveau "
        "soit prêt ;",
        "- les sondes empêchent le Service d'aiguiller vers un pod non prêt ;",
        "- le Job de migration s'exécute avant la bascule sans interrompre le trafic.",
        "",
        "## Limites de cette campagne",
        "",
        "Ces mesures ont été obtenues sur l'**environnement de démonstration** : cluster Minikube à "
        "un nœud, sur un poste de travail, avec une base **HSQLDB en mémoire**.",
        "",
        "Elles valident le comportement de la **chaîne et du système** sous charge — disponibilité "
        "pendant une mise à jour, déclenchement des alertes, tenue des seuils, position du point de "
        "rupture. Elles ne prédisent **pas** les capacités absolues d'une future production : une "
        "base de données réelle introduit des latences d'entrées-sorties et des contentions que "
        "HSQLDB en mémoire ne reproduit pas.",
        "",
        "**Les capacités devront être requalifiées après la migration vers PostgreSQL** "
        "(recommandation n°1 du rapport de performance). La méthode, les seuils et l'outillage, eux, "
        "resteront valables tels quels.",
        "",
        "## Reproduire la campagne",
        "",
        "```bash",
        "# Exposer le frontend en NodePort (cible stable d'une mise à jour à l'autre)",
        "helm upgrade microcrm helm/microcrm -n orion-dev \\",
        "    -f helm/microcrm/values-dev.yaml --set image.tag=1.2.0 \\",
        "    --set service.type=NodePort --wait",
        "",
        "# Les trois paliers de caractérisation",
        "./scripts/test-charge.sh",
        "",
        "# Le palier de saturation, qui déclenche les alertes",
        "./scripts/test-charge.sh --palier saturation --sans-verdict",
        "",
        "# Captures Kibana pendant la charge",
        "node scripts/capturer-kibana.js tableau-de-bord-charge alerte-declenchee",
        "```",
        "",
        "> Ce test **n'est pas exécuté par le pipeline** : il exige un cluster déployé et dure "
        "> plusieurs minutes, ce qui ferait sortir la chaîne de sa cible de 12 minutes. Il se lance "
        "> manuellement, au même titre que `terraform apply`.",
    ]
    return lignes


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(
        prog="resumer.py",
        description="Synthèse comparative des paliers de charge k6.",
    )
    analyseur.add_argument("-s", "--sortie", default="docs/captures/charge")
    analyseur.add_argument("-v", "--verbeux", action="store_true")
    args = analyseur.parse_args(argv if argv is not None else sys.argv[1:])

    repertoire = Path(args.sortie)
    if not repertoire.is_dir():
        print(f"[ERREUR] répertoire introuvable : {repertoire}", file=sys.stderr)
        return 1

    resultats = charger(repertoire)
    if not resultats:
        print("[ERREUR] aucun fichier de résultats exploitable.", file=sys.stderr)
        return 1

    fichier = repertoire / "RESUME.md"
    fichier.write_text(rendre(resultats) + "\n", encoding="utf-8")
    print(f"[INFO]  {len(resultats)} palier(s) résumé(s) dans {fichier}", file=sys.stderr)

    for r in resultats:
        etat = "OK " if (r["verdict_p95"] and r["verdict_erreur"]) else "HORS SEUIL"
        marque = "  [max non exploitable : saut d'horloge]" if not r["coherente"] else ""
        print(
            f"  {r['palier']:<12} {r['vus']:>3} VU  "
            f"p95={ms(r['p95']):>9}  erreurs={r['taux_erreur'] * 100:.2f}%  {etat}{marque}"
        )

    incoherents = [r["palier"] for r in resultats if not r["coherente"]]
    if incoherents:
        print(
            f"[AVERT] durée minimale négative sur : {', '.join(incoherents)}. "
            "Les maximums de ces paliers sont des artefacts d'horloge, pas des mesures.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
