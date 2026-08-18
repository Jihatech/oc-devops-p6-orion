#!/usr/bin/env python3
"""Génère les objets sauvegardés Kibana (visualisations Lens + tableau de bord).

Écrire ces objets à la main serait interminable et illisible ; les générer
garantit qu'ils restent cohérents entre eux (identifiants, références,
disposition) et qu'ils sont versionnables.
"""
import json
import sys

VUE_K8S = "orion-k8s"
VUE_DORA = "orion-dora"


def colonne_date(champ="@timestamp"):
    return {
        "label": "Horodatage",
        "dataType": "date",
        "operationType": "date_histogram",
        "sourceField": champ,
        "isBucketed": True,
        "scale": "interval",
        "params": {"interval": "auto", "includeEmptyRows": True},
    }


def lens(identifiant, titre, description, vue, couches, visualisation, type_vis="lnsXY"):
    etat = {
        "visualization": visualisation,
        "query": {"query": "", "language": "kuery"},
        "filters": [],
        "datasourceStates": {"formBased": {"layers": couches}},
        "internalReferences": [],
        "adHocDataViews": {},
    }
    references = [
        {
            "type": "index-pattern",
            "id": vue,
            "name": f"indexpattern-datasource-layer-{cle}",
        }
        for cle in couches
    ]
    return {
        "id": identifiant,
        "type": "lens",
        "attributes": {
            "title": titre,
            "description": description,
            "visualizationType": type_vis,
            "state": etat,
        },
        "references": references,
        "coreMigrationVersion": "8.8.0",
        "typeMigrationVersion": "8.9.0",
    }


# --- 1. Disponibilité : répartition des codes HTTP dans le temps --------------
vis_disponibilite = lens(
    "orion-vis-disponibilite",
    "Disponibilité — codes de réponse HTTP",
    "Répartition des codes HTTP servis par le frontend. Une bascule vers les 5xx signale une indisponibilité.",
    VUE_K8S,
    {
        "couche1": {
            "columns": {
                "col_date": colonne_date(),
                "col_status": {
                    "label": "Code HTTP",
                    "dataType": "number",
                    "operationType": "terms",
                    "sourceField": "json.status",
                    "isBucketed": True,
                    "scale": "ordinal",
                    "params": {"size": 10, "orderBy": {"type": "column", "columnId": "col_count"},
                               "orderDirection": "desc", "otherBucket": False, "missingBucket": False},
                },
                "col_count": {
                    "label": "Requêtes",
                    "dataType": "number",
                    "operationType": "count",
                    "sourceField": "___records___",
                    "isBucketed": False,
                    "scale": "ratio",
                },
            },
            "columnOrder": ["col_date", "col_status", "col_count"],
            "incompleteColumns": {},
        }
    },
    {
        "legend": {"isVisible": True, "position": "right"},
        "valueLabels": "hide",
        "preferredSeriesType": "bar_stacked",
        "layers": [{
            "layerId": "couche1",
            "layerType": "data",
            "seriesType": "bar_stacked",
            "xAccessor": "col_date",
            "splitAccessor": "col_status",
            "accessors": ["col_count"],
        }],
    },
)

# --- 2. Performance : temps de réponse médian et p95 -------------------------
vis_performance = lens(
    "orion-vis-performance",
    "Performance — temps de réponse (médiane et 95e centile)",
    "Durée de traitement des requêtes. Le 95e centile révèle les lenteurs que la médiane masque.",
    VUE_K8S,
    {
        "couche1": {
            "columns": {
                "col_date": colonne_date(),
                "col_median": {
                    "label": "Médiane (s)",
                    "dataType": "number",
                    "operationType": "median",
                    "sourceField": "json.duree_s",
                    "isBucketed": False,
                    "scale": "ratio",
                },
                "col_p95": {
                    "label": "95e centile (s)",
                    "dataType": "number",
                    "operationType": "percentile",
                    "sourceField": "json.duree_s",
                    "isBucketed": False,
                    "scale": "ratio",
                    "params": {"percentile": 95},
                },
            },
            "columnOrder": ["col_date", "col_median", "col_p95"],
            "incompleteColumns": {},
        }
    },
    {
        "legend": {"isVisible": True, "position": "right"},
        "valueLabels": "hide",
        "preferredSeriesType": "line",
        "layers": [{
            "layerId": "couche1",
            "layerType": "data",
            "seriesType": "line",
            "xAccessor": "col_date",
            "accessors": ["col_median", "col_p95"],
        }],
    },
)

# --- 3. Sécurité : erreurs client par URI ------------------------------------
vis_securite = lens(
    "orion-vis-securite",
    "Sécurité — erreurs client 4xx par URI",
    "Requêtes rejetées, regroupées par chemin. Une concentration sur un chemin peut trahir un balayage.",
    VUE_K8S,
    {
        "couche1": {
            "columns": {
                "col_uri": {
                    "label": "URI",
                    "dataType": "string",
                    "operationType": "terms",
                    "sourceField": "json.uri",
                    "isBucketed": True,
                    "scale": "ordinal",
                    "params": {"size": 10, "orderBy": {"type": "column", "columnId": "col_count"},
                               "orderDirection": "desc", "otherBucket": True, "missingBucket": False},
                },
                "col_count": {
                    "label": "Erreurs",
                    "dataType": "number",
                    "operationType": "count",
                    "sourceField": "___records___",
                    "isBucketed": False,
                    "scale": "ratio",
                    "filter": {"query": "json.status >= 400 and json.status < 500", "language": "kuery"},
                },
            },
            "columnOrder": ["col_uri", "col_count"],
            "incompleteColumns": {},
        }
    },
    {
        "legend": {"isVisible": True, "position": "right"},
        "valueLabels": "hide",
        "preferredSeriesType": "bar_horizontal",
        "layers": [{
            "layerId": "couche1",
            "layerType": "data",
            "seriesType": "bar_horizontal",
            "xAccessor": "col_uri",
            "accessors": ["col_count"],
        }],
    },
)

# --- 4. Volume de journaux par composant ------------------------------------
vis_composants = lens(
    "orion-vis-composants",
    "Journaux par composant",
    "Volume de journaux émis par chaque composant. Un silence soudain est un signal aussi fort qu'une rafale d'erreurs.",
    VUE_K8S,
    {
        "couche1": {
            "columns": {
                "col_composant": {
                    "label": "Composant",
                    "dataType": "string",
                    "operationType": "terms",
                    "sourceField": "kubernetes.labels.app_kubernetes_io/component",
                    "isBucketed": True,
                    "scale": "ordinal",
                    "params": {"size": 5, "orderBy": {"type": "column", "columnId": "col_count"},
                               "orderDirection": "desc", "otherBucket": True, "missingBucket": False},
                },
                "col_count": {
                    "label": "Lignes",
                    "dataType": "number",
                    "operationType": "count",
                    "sourceField": "___records___",
                    "isBucketed": False,
                    "scale": "ratio",
                },
            },
            "columnOrder": ["col_composant", "col_count"],
            "incompleteColumns": {},
        }
    },
    {
        "shape": "donut",
        "layers": [{
            "layerId": "couche1",
            "layerType": "data",
            "primaryGroups": ["col_composant"],
            "metrics": ["col_count"],
            "numberDisplay": "percent",
            "categoryDisplay": "default",
            "legendDisplay": "default",
            "nestedLegend": False,
        }],
    },
    type_vis="lnsPie",
)

# --- 5. Indicateurs DORA -----------------------------------------------------
vis_dora = lens(
    "orion-vis-dora",
    "Indicateurs DORA",
    "Dernière valeur mesurée pour chacun des quatre indicateurs DORA.",
    VUE_DORA,
    {
        "couche1": {
            "columns": {
                "col_indicateur": {
                    "label": "Indicateur",
                    "dataType": "string",
                    "operationType": "terms",
                    "sourceField": "indicateur",
                    "isBucketed": True,
                    "scale": "ordinal",
                    "params": {"size": 10, "orderBy": {"type": "alphabetical"},
                               "orderDirection": "asc", "otherBucket": False, "missingBucket": False},
                },
                "col_valeur": {
                    "label": "Valeur",
                    "dataType": "number",
                    "operationType": "last_value",
                    "sourceField": "valeur",
                    "isBucketed": False,
                    "scale": "ratio",
                    "params": {"sortField": "@timestamp", "showArrayValues": False},
                },
            },
            "columnOrder": ["col_indicateur", "col_valeur"],
            "incompleteColumns": {},
        }
    },
    {
        "layerId": "couche1",
        "layerType": "data",
        "columns": [
            {"columnId": "col_indicateur", "isTransposed": False},
            {"columnId": "col_valeur", "isTransposed": False},
        ],
    },
    type_vis="lnsDatatable",
)

panneaux = []
positions = [
    ("orion-vis-disponibilite", 0, 0, 24, 15),
    ("orion-vis-performance", 24, 0, 24, 15),
    ("orion-vis-securite", 0, 15, 24, 15),
    ("orion-vis-composants", 24, 15, 12, 15),
    ("orion-vis-dora", 36, 15, 12, 15),
]
references_tdb = []
for index, (identifiant, x, y, w, h) in enumerate(positions):
    nom_panneau = f"panel_{index}"
    panneaux.append({
        "version": "8.15.3",
        "type": "lens",
        "gridData": {"x": x, "y": y, "w": w, "h": h, "i": nom_panneau},
        "panelIndex": nom_panneau,
        "embeddableConfig": {"enhancements": {}},
        "panelRefName": nom_panneau,
    })
    references_tdb.append({"name": nom_panneau, "type": "lens", "id": identifiant})

tableau_de_bord = {
    "id": "orion-tdb-microcrm",
    "type": "dashboard",
    "attributes": {
        "title": "MicroCRM — disponibilité, performance et sécurité",
        "description": (
            "Tableau de bord d'exploitation d'Orion. Répond à la lacune S7 de l'audit : "
            "aucun journal centralisé, aucune vue d'ensemble. Les trois dimensions attendues "
            "y figurent, plus les indicateurs DORA."
        ),
        "panelsJSON": json.dumps(panneaux, ensure_ascii=False),
        "optionsJSON": json.dumps({"useMargins": True, "syncColors": False, "hidePanelTitles": False}),
        "timeRestore": True,
        "timeFrom": "now-24h",
        "timeTo": "now",
        "refreshInterval": {"pause": False, "value": 60000},
        "kibanaSavedObjectMeta": {
            "searchSourceJSON": json.dumps({"query": {"query": "", "language": "kuery"}, "filter": []})
        },
    },
    "references": references_tdb,
    "coreMigrationVersion": "8.8.0",
    "typeMigrationVersion": "8.9.0",
}

objets = [vis_disponibilite, vis_performance, vis_securite, vis_composants, vis_dora, tableau_de_bord]

sortie = sys.argv[1] if len(sys.argv) > 1 else "elk/kibana/objets-sauvegardes.ndjson"
with open(sortie, "w", encoding="utf-8") as flux:
    for objet in objets:
        flux.write(json.dumps(objet, ensure_ascii=False) + "\n")
print(f"{len(objets)} objets écrits dans {sortie}")
