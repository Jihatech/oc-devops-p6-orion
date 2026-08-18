#!/usr/bin/env bash
# =============================================================================
# elk-setup.sh — Configuration de la stack ELK d'Orion
# =============================================================================
#
# BUT
#   Rendre la stack ELK exploitable et REPRODUCTIBLE : modèle d'index, vues de
#   données, tableaux de bord et règles d'alerte sont créés par script, à
#   partir de définitions versionnées dans `elk/kibana/`.
#
#   Une configuration Kibana construite à la souris n'existe que dans le
#   volume de la machine qui l'a construite. Si le volume est perdu, tout est
#   perdu — et personne ne peut la reproduire. C'est exactement le type de
#   travail manuel non traçable que ce projet vise à éliminer (faiblesse f3
#   de l'audit).
#
# FONCTIONNEMENT
#   1. Attend que Elasticsearch et Kibana répondent.
#   2. Applique le modèle d'index (types de champs déclarés explicitement).
#   3. Crée les vues de données (data views) sur les index orion-*.
#   4. Importe les objets sauvegardés (tableaux de bord, visualisations).
#   5. Crée les règles d'alerte : disponibilité, performance, sécurité.
#   6. Affiche un récapitulatif de ce qui existe réellement côté serveur.
#
#   Le script est IDEMPOTENT : il peut être rejoué sans créer de doublons
#   (les objets sont créés avec un identifiant fixe et écrasés).
#
# PARAMÈTRES
#   -e, --elasticsearch <url>   URL d'Elasticsearch   (défaut : http://localhost:9200)
#   -k, --kibana <url>          URL de Kibana         (défaut : http://localhost:5601)
#   -d, --delai <secondes>      Délai d'attente       (défaut : 300)
#       --sans-alertes          N'installe pas les règles d'alerte
#   -v, --verbeux               Journalisation détaillée
#   -h, --aide                  Affiche cette aide
#
# CONDITIONS D'EXÉCUTION
#   - La stack doit être démarrée : docker compose -f elk/docker-compose.yml up -d
#   - curl et python3 disponibles.
#   - Aucun secret manipulé : la stack locale fonctionne sans authentification
#     (écart documenté dans elk/README.md).
#   - Codes de sortie : 0 succès · 1 erreur · 2 prérequis manquant
#
# EXEMPLES
#   ./scripts/elk-setup.sh
#   ./scripts/elk-setup.sh --sans-alertes --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

ES="http://localhost:9200"
KIBANA="http://localhost:5601"
DELAI=300
ALERTES=1

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--elasticsearch) ES="${2:?url requise}" ; shift 2 ;;
            -k|--kibana)        KIBANA="${2:?url requise}" ; shift 2 ;;
            -d|--delai)         DELAI="${2:?délai requis}" ; shift 2 ;;
            --sans-alertes)     ALERTES=0 ; shift ;;
            -v|--verbeux)       export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)          afficher_aide ; exit 0 ;;
            *)                  mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

attendre_service() {
    local nom="$1" url="$2" motif="$3"
    log_info "attente de $nom…"
    local ecoule=0
    while [[ $ecoule -lt $DELAI ]]; do
        if curl -sf --max-time 5 "$url" 2>/dev/null | grep -q "$motif"; then
            log_ok "$nom disponible après ${ecoule}s"
            return 0
        fi
        sleep 5
        ecoule=$((ecoule + 5))
    done
    log_erreur "$nom indisponible après ${DELAI}s"
    return 1
}

# Appel à l'API Kibana. L'en-tête kbn-xsrf est OBLIGATOIRE sur toute écriture :
# sans lui, Kibana refuse la requête avec un message peu explicite.
api_kibana() {
    local methode="$1" chemin="$2" donnees="${3:-}"
    if [[ -n "$donnees" ]]; then
        curl -sS -X "$methode" "$KIBANA$chemin" \
            -H "kbn-xsrf: true" -H "Content-Type: application/json" \
            -d "$donnees"
    else
        curl -sS -X "$methode" "$KIBANA$chemin" -H "kbn-xsrf: true"
    fi
}

creer_modele_index() {
    local racine="$1"
    log_titre "Modèle d'index Elasticsearch"
    local reponse
    reponse=$(curl -sS -X PUT "$ES/_index_template/orion" \
        -H "Content-Type: application/json" \
        -d @"$racine/elk/kibana/index-template.json")
    if grep -q '"acknowledged":true' <<<"$reponse"; then
        log_ok "modèle « orion » appliqué"
    else
        log_erreur "échec de l'application du modèle : $reponse"
        return 1
    fi
}

creer_vues_donnees() {
    log_titre "Vues de données Kibana"
    # Identifiants FIXES : rejouer le script met à jour la vue existante au
    # lieu d'en créer une seconde. C'est ce qui rend le script idempotent.
    local -a vues=(
        "orion-logs|orion-logs-*|Journaux des conteneurs"
        "orion-k8s|orion-k8s-*|Journaux des pods Kubernetes"
        "orion-dora|orion-dora-*|Indicateurs DORA"
    )
    local vue id motif titre
    for vue in "${vues[@]}"; do
        IFS='|' read -r id motif titre <<<"$vue"
        api_kibana DELETE "/api/data_views/data_view/$id" >/dev/null 2>&1 || true
        local corps
        corps=$(printf '{"data_view":{"id":"%s","title":"%s","name":"%s","timeFieldName":"@timestamp"}}' \
            "$id" "$motif" "$titre")
        if api_kibana POST "/api/data_views/data_view" "$corps" | grep -q '"id"'; then
            log_ok "vue « $titre » ($motif)"
        else
            log_avert "vue « $titre » non créée"
        fi
    done
}

importer_objets() {
    local racine="$1"
    local fichier="$racine/elk/kibana/objets-sauvegardes.ndjson"
    log_titre "Tableaux de bord et visualisations"
    if [[ ! -f "$fichier" ]]; then
        log_avert "objets-sauvegardes.ndjson absent : import ignoré"
        return 0
    fi
    local reponse
    reponse=$(curl -sS -X POST "$KIBANA/api/saved_objects/_import?overwrite=true" \
        -H "kbn-xsrf: true" -F "file=@$fichier")
    local succes
    succes=$(sed -n 's/.*"successCount": *\([0-9]*\).*/\1/p' <<<"$reponse")
    if [[ "${succes:-0}" -gt 0 ]]; then
        log_ok "${succes} objet(s) importé(s)"
    else
        log_avert "aucun objet importé : $(head -c 300 <<<"$reponse")"
    fi
}

creer_regles_alerte() {
    local racine="$1"
    log_titre "Règles d'alerte"
    local fichier
    for fichier in "$racine"/elk/kibana/regles/*.json; do
        [[ -f "$fichier" ]] || continue
        local nom
        nom=$(basename "$fichier" .json)
        # Les règles portant le même nom sont supprimées avant recréation :
        # l'API des règles ne propose pas d'écrasement par identifiant.
        local existantes
        existantes=$(api_kibana GET "/api/alerting/rules/_find?per_page=100" 2>/dev/null || echo "")
        local id
        id=$(python3 -c "
import json, sys
try:
    donnees = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
cible = json.load(open('$fichier', encoding='utf-8'))['name']
for regle in donnees.get('data', []):
    if regle.get('name') == cible:
        print(regle['id'])
        break
" <<<"$existantes" 2>/dev/null || true)
        [[ -n "$id" ]] && api_kibana DELETE "/api/alerting/rule/$id" >/dev/null 2>&1 || true

        local reponse
        reponse=$(api_kibana POST "/api/alerting/rule" "$(cat "$fichier")")
        if grep -q '"id"' <<<"$reponse"; then
            log_ok "règle « $nom » créée"
        else
            log_erreur "règle « $nom » : $(head -c 300 <<<"$reponse")"
        fi
    done
}

recapituler() {
    log_titre "État réel du serveur"
    log_info "index :"
    curl -sS "$ES/_cat/indices/orion-*?h=index,docs.count,store.size" | sort | sed 's/^/    /'
    log_info "vues de données :"
    api_kibana GET "/api/data_views" 2>/dev/null | python3 -c "
import json, sys
try:
    for vue in json.load(sys.stdin).get('data_view', []):
        print('    %-30s %s' % (vue.get('title'), vue.get('name', '')))
except Exception:
    print('    (lecture impossible)')
" || true
    log_info "règles d'alerte :"
    api_kibana GET "/api/alerting/rules/_find?per_page=100" 2>/dev/null | python3 -c "
import json, sys
try:
    donnees = json.load(sys.stdin)
    for regle in donnees.get('data', []):
        print('    %-45s %s' % (regle.get('name'), 'activée' if regle.get('enabled') else 'désactivée'))
    if not donnees.get('data'):
        print('    (aucune)')
except Exception:
    print('    (lecture impossible)')
" || true
}

principal() {
    analyser_arguments "$@"
    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)

    exiger_commandes curl python3

    log_titre "Configuration de la stack ELK"
    log_info "Elasticsearch : $ES"
    log_info "Kibana        : $KIBANA"

    attendre_service "Elasticsearch" "$ES/_cluster/health" '"status"' || mourir "Elasticsearch injoignable" 1
    attendre_service "Kibana" "$KIBANA/api/status" '"available"' || mourir "Kibana injoignable" 1

    creer_modele_index "$racine"
    creer_vues_donnees
    importer_objets "$racine"
    [[ $ALERTES -eq 1 ]] && creer_regles_alerte "$racine"

    recapituler

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"
    log_info "Kibana : $KIBANA/app/dashboards"
}

principal "$@"
