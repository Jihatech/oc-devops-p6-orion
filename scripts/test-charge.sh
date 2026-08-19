#!/usr/bin/env bash
# =============================================================================
# test-charge.sh — Campagne de tests de charge de MicroCRM
# =============================================================================
#
# BUT
#   Mesurer la tenue de l'application déployée sur Kubernetes sous plusieurs
#   niveaux de charge, et rendre un VERDICT pass/fail à partir de seuils
#   explicites. Répond à l'étape 5 de la partie 2 de la mission, et complète
#   le plan de tests (docs/04-plan-tests.md, type T17).
#
#   Un test de charge sans seuil n'est qu'une mesure. Ce sont les seuils qui
#   en font un test : ils transforment un chiffre en décision.
#
# FONCTIONNEMENT
#   1. Vérifie les prérequis et l'accessibilité de l'application.
#   2. Exécute successivement les paliers demandés (nominal, soutenu, pointe).
#      Chaque palier comporte un ÉCHAUFFEMENT, exclu des statistiques, puis
#      une phase de MESURE sur laquelle portent les seuils.
#   3. Écrit un fichier de résultats JSON par palier, puis un RESUME.md
#      comparatif.
#   4. Retourne un code d'échec si un seuil est dépassé, afin que la campagne
#      soit exploitable comme une porte de qualité.
#
#   k6 s'exécute EN CONTENEUR, attaché au réseau Docker de Minikube. Ce choix
#   évite deux écueils :
#     - aucune installation sur le poste : l'évaluateur reproduit la campagne
#       avec Docker seul ;
#     - aucun `kubectl port-forward` : ce dernier est un proxy à connexion
#       unique qui deviendrait lui-même le goulot d'étranglement et ferait
#       mesurer le tunnel plutôt que l'application.
#
# PARAMÈTRES
#   -p, --palier <nominal|soutenu|pointe|saturation|tous>
#                              Palier à exécuter                 (défaut : tous)
#   -u, --url <url>            URL de base       (défaut : http://<ip-minikube>:30080)
#   -s, --sortie <répertoire>  Résultats         (défaut : docs/captures/charge)
#   -d, --duree <durée k6>     Durée de mesure par palier   (défaut : par palier)
#   -e, --echauffement <durée> Durée d'échauffement         (défaut : 30s)
#       --seuil-p95 <ms>       Seuil du 95e centile         (défaut : 500)
#       --seuil-erreur <taux>  Taux d'erreur maximal        (défaut : 0.01)
#       --sans-verdict         Mesure sans faire échouer sur seuil dépassé
#   -n, --simulation           Affiche le plan sans rien exécuter
#   -v, --verbeux              Journalisation détaillée
#   -h, --aide                 Affiche cette aide
#
# PALIERS
#   nominal   5 utilisateurs virtuels  — usage courant de l'équipe d'Orion
#   soutenu  25 utilisateurs virtuels  — pointe d'activité plausible
#   pointe   50 utilisateurs virtuels  — au-delà de l'usage attendu, pour
#                                        observer le comportement en surcharge
#
#   saturation  300 utilisateurs virtuels — hors de tout usage réaliste. Ce
#               palier ne caractérise PAS l'application : il sert à vérifier
#               que la chaîne d'alerte se déclenche réellement. Il n'est pas
#               inclus dans « tous » et se lance explicitement.
#
# CONDITIONS D'EXÉCUTION
#   - Cluster Kubernetes démarré et application déployée dans le namespace visé.
#   - Le Service frontend doit être exposé en NodePort (port 30080) :
#       helm upgrade ... --set service.type=NodePort
#   - Docker installé et démon démarré ; réseau Docker « minikube » présent.
#   - AUCUNE exécution dans la CI : ce test exige un cluster déployé et dure
#     plusieurs minutes, ce qui ferait sortir le pipeline de sa cible de
#     12 minutes. Il se lance manuellement, comme `terraform apply`.
#   - Aucun secret manipulé. Aucun privilège root.
#   - Codes de sortie : 0 tous les seuils tenus · 1 seuil dépassé
#     · 2 prérequis manquant · 3 paramètre invalide
#
# EXEMPLES
#   ./scripts/test-charge.sh
#   ./scripts/test-charge.sh --palier pointe --duree 3m
#   ./scripts/test-charge.sh --simulation --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

# Image épinglée PAR DIGEST, comme les images applicatives : une version d'outil
# de mesure qui change en silence rendrait deux campagnes incomparables.
# Sous Git Bash (Windows), MSYS réécrit tout argument ressemblant à un chemin
# POSIX : « /scenario/scenario.js » devient « C:/Program Files/Git/scenario/... »
# et k6 ne trouve plus son fichier. Cette variable désactive la conversion.
# Elle est sans effet sur Linux et macOS, où elle n'existe simplement pas.
export MSYS_NO_PATHCONV=1

IMAGE_K6="grafana/k6:0.55.0@sha256:f0573f397c9de5ce0635bec9ece3e3f1387b410b54dbe72d9b3f2a57ce8f2490"
RESEAU="minikube"

PALIER="tous"
URL=""
SORTIE="docs/captures/charge"
DUREE=""
ECHAUFFEMENT="30s"
SEUIL_P95=500
SEUIL_ERREUR="0.01"
VERDICT=1
SIMULATION=0

ECHECS=0

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--palier)
                PALIER="${2:-}"
                case "$PALIER" in
                    nominal|soutenu|pointe|saturation|tous) ;;
                    *) mourir "palier invalide : « ${PALIER:-vide} » (attendu : nominal, soutenu, pointe ou tous)" 3 ;;
                esac
                shift 2 ;;
            -u|--url)          URL="${2:?url requise}" ; shift 2 ;;
            -s|--sortie)       SORTIE="${2:?répertoire requis}" ; shift 2 ;;
            -d|--duree)        DUREE="${2:?durée requise}" ; shift 2 ;;
            -e|--echauffement) ECHAUFFEMENT="${2:?durée requise}" ; shift 2 ;;
            --seuil-p95)
                SEUIL_P95="${2:-}"
                [[ "$SEUIL_P95" =~ ^[0-9]+$ ]] || mourir "seuil p95 invalide : « ${SEUIL_P95:-vide} »" 3
                shift 2 ;;
            --seuil-erreur)    SEUIL_ERREUR="${2:?taux requis}" ; shift 2 ;;
            --sans-verdict)    VERDICT=0 ; shift ;;
            -n|--simulation)   SIMULATION=1 ; shift ;;
            -v|--verbeux)      export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)         afficher_aide ; exit 0 ;;
            *)                 mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

# Paramètres de chaque palier : utilisateurs virtuels et durée de mesure.
parametres_palier() {
    case "$1" in
        nominal) printf '5 2m\n' ;;
        soutenu) printf '25 3m\n' ;;
        pointe)  printf '50 3m\n' ;;
        # Palier délibérément hors de tout usage réaliste : il ne sert pas à
        # caractériser l'application mais à VÉRIFIER QUE LA CHAÎNE D'ALERTE
        # SE DÉCLENCHE. Une alerte configurée mais jamais éprouvée n'est
        # qu'une intention.
        saturation) printf '300 4m\n' ;;
        *)       return 1 ;;
    esac
}

determiner_url() {
    [[ -n "$URL" ]] && return 0
    exiger_commandes minikube
    local ip
    ip=$(minikube ip 2>/dev/null || true)
    [[ -n "$ip" ]] || mourir "impossible de déterminer l'IP de Minikube — fournissez --url" 2
    URL="http://${ip}:30080"
    log_debug "URL déduite : $URL"
}

verifier_cible() {
    log_info "vérification de l'accessibilité de $URL"
    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] contrôle d'accessibilité ignoré"
        return 0
    fi
    local code
    code=$(docker run --rm --network "$RESEAU" curlimages/curl:8.11.1 \
        -s -o /dev/null -w '%{http_code}' --max-time 15 "$URL/api/persons" 2>/dev/null || echo "000")
    if [[ "$code" != "200" ]]; then
        log_erreur "l'application ne répond pas (code $code) sur $URL"
        log_info  "Vérifiez : kubectl get svc -n orion-dev  (le Service doit être en NodePort 30080)"
        return 1
    fi
    log_ok "application accessible (HTTP 200)"
}

executer_palier() {
    local palier="$1" racine="$2" sortie="$3"
    local vus duree
    read -r vus duree <<<"$(parametres_palier "$palier")"
    [[ -n "$DUREE" ]] && duree="$DUREE"

    log_titre "Palier « $palier » — $vus utilisateurs virtuels, mesure ${duree} (échauffement ${ECHAUFFEMENT})"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] k6 run avec VUS=$vus DUREE=$duree PALIER=$palier"
        return 0
    fi

    local code=0
    docker run --rm \
        --network "$RESEAU" \
        --volume "$racine/scripts/charge:/scenario:ro" \
        --volume "$sortie:/resultats" \
        --env "BASE_URL=$URL" \
        --env "VUS=$vus" \
        --env "DUREE=$duree" \
        --env "ECHAUFFEMENT=$ECHAUFFEMENT" \
        --env "PALIER=$palier" \
        --env "SEUIL_P95=$SEUIL_P95" \
        --env "SEUIL_ERREUR=$SEUIL_ERREUR" \
        "$IMAGE_K6" run /scenario/scenario.js || code=$?

    if [[ $code -ne 0 ]]; then
        # k6 retourne 99 lorsqu'un seuil est dépassé : ce n'est pas une panne
        # du test, c'est son verdict.
        log_avert "palier « $palier » : au moins un seuil dépassé (code k6 $code)"
        ECHECS=$((ECHECS + 1))
    else
        log_ok "palier « $palier » : tous les seuils tenus"
    fi

    [[ -f "$sortie/resultats-$palier.json" ]] \
        || log_avert "fichier de résultats absent pour le palier « $palier »"
}

# Agrège les résultats des paliers en un document comparatif. La logique est
# déportée dans un script Python : l'analyse de JSON en Bash serait fragile, et
# c'est le résumé — pas le JSON brut — qui alimentera le rapport de performance.
generer_resume() {
    local racine="$1" sortie="$2"
    log_titre "Synthèse comparative"
    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] génération de RESUME.md"
        return 0
    fi
    if python3 "$racine/scripts/charge/resumer.py" --sortie "$sortie"; then
        log_ok "RESUME.md écrit dans $sortie"
    else
        log_avert "synthèse non générée"
    fi
}

principal() {
    analyser_arguments "$@"
    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)

    exiger_commandes docker
    docker info >/dev/null 2>&1 || mourir "le démon Docker ne répond pas." 2

    [[ "$SORTIE" = /* ]] || SORTIE="$racine/$SORTIE"
    mkdir -p "$SORTIE"

    determiner_url

    log_titre "Campagne de charge — MicroCRM"
    log_info "cible          : $URL"
    log_info "image k6       : ${IMAGE_K6%%@*} (épinglée par digest)"
    log_info "seuils         : p95 < ${SEUIL_P95} ms · erreurs < $(python3 -c "print(f'{float('$SEUIL_ERREUR')*100:.1f}')" 2>/dev/null || echo "1.0") %"
    log_info "résultats      : $SORTIE"

    verifier_cible || mourir "cible injoignable" 2

    local -a paliers
    if [[ "$PALIER" == "tous" ]]; then
        # « saturation » est volontairement exclu : il n'a pas vocation à
        # caractériser l'application, et son verdict n'aurait pas de sens.
        paliers=(nominal soutenu pointe)
    else
        paliers=("$PALIER")
    fi

    local p
    for p in "${paliers[@]}"; do
        executer_palier "$p" "$racine" "$SORTIE"
    done

    generer_resume "$racine" "$SORTIE"

    local duree_totale=$(( $(date +%s) - debut ))
    log_titre "Campagne terminée en $(duree_lisible "$duree_totale")"

    if [[ $ECHECS -gt 0 ]]; then
        if [[ $VERDICT -eq 0 ]]; then
            log_avert "$ECHECS palier(s) hors seuils — ignoré (--sans-verdict)"
            exit 0
        fi
        mourir "$ECHECS palier(s) ont dépassé les seuils." 1
    fi
    log_ok "tous les paliers respectent les seuils."
}

principal "$@"
