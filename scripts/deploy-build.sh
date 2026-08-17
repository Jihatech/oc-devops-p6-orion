#!/usr/bin/env bash
# =============================================================================
# deploy-build.sh — Déploiement des builds de MicroCRM
# =============================================================================
#
# BUT
#   Déployer les artefacts produits par la chaîne d'intégration continue vers un
#   environnement d'exécution, de façon reproductible et vérifiée. Remplace le
#   déploiement manuel par commandes `docker` réalisé aujourd'hui par l'équipe
#   Ops (goulot G3 de l'audit : 2 personnes, aucune traçabilité, non rejouable).
#
#   Le script ne se contente pas de démarrer les conteneurs : il VÉRIFIE que le
#   service répond avant de déclarer le déploiement réussi, et remet
#   automatiquement l'état antérieur si ce n'est pas le cas. Un déploiement qui
#   n'est pas vérifié n'est pas un déploiement : c'est un espoir.
#
# FONCTIONNEMENT
#   1. Valide les paramètres (cible, environnement, version) et les prérequis.
#   2. Construit les images à partir du Dockerfile multi-étages fourni, en
#      étiquetant chaque image avec la version demandée ET le SHA du commit
#      (traçabilité — faiblesse f4 de l'audit).
#   3. Arrête et conserve la référence des conteneurs en place (état N-1).
#   4. Démarre les nouveaux conteneurs sur les ports de l'environnement visé.
#   5. Sonde le service jusqu'à obtention d'une réponse (test de fumée), dans
#      la limite du délai imparti.
#   6. Si la sonde échoue : ROLLBACK automatique vers l'image précédente, et
#      sortie en erreur. Sinon, affiche le récapitulatif du déploiement.
#
#   Cibles de déploiement (--cible) :
#     docker      conteneurs Docker locaux — implémenté (phase 2)
#     kubernetes  déploiement Helm sur Minikube — ajouté en phase 4
#
# PARAMÈTRES
#   -c, --composant <front|back|tous>   Composant à déployer      (défaut : tous)
#   -e, --environnement <dev|staging|prod>  Environnement visé    (défaut : dev)
#       --cible <docker|kubernetes>     Mode de déploiement       (défaut : docker)
#   -V, --version <version>             Étiquette de version      (défaut : SHA court du commit)
#   -p, --port-front <n>                Port hôte du frontend     (défaut : 8081)
#   -P, --port-back <n>                 Port hôte du backend      (défaut : 8080)
#   -d, --delai <secondes>              Délai max du test de fumée (défaut : 90)
#       --sans-rollback                 Désactive le retour arrière automatique
#                                       (diagnostic : laisse l'état en échec)
#   -n, --simulation                    N'exécute rien : affiche le plan
#   -v, --verbeux                       Journalisation détaillée
#   -h, --aide                          Affiche cette aide
#
# CONDITIONS D'EXÉCUTION
#   - Docker installé et démon DÉMARRÉ (vérifié explicitement : un démon
#     éteint est la cause d'échec la plus fréquente sous Windows/macOS).
#   - Les artefacts doivent avoir été construits au préalable, ou le
#     Dockerfile doit pouvoir les reconstruire (il embarque ses propres étages
#     de build).
#   - Ports hôtes disponibles.
#   - Aucun privilège root si l'utilisateur appartient au groupe `docker`.
#   - Aucun secret n'est passé en ligne de commande ni journalisé : les
#     credentials éventuels transitent par des variables d'environnement ou
#     des secrets Kubernetes.
#   - Codes de sortie : 0 succès · 1 erreur de déploiement · 2 prérequis
#     manquant · 3 paramètre invalide · 6 test de fumée en échec (rollback
#     effectué) · 7 cible non encore implémentée
#
# EXEMPLES
#   ./scripts/deploy-build.sh
#   ./scripts/deploy-build.sh --composant back --environnement staging -V 1.2.0
#   ./scripts/deploy-build.sh --simulation --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

COMPOSANT="tous"
ENVIRONNEMENT="dev"
CIBLE="docker"
VERSION=""
PORT_FRONT=8081
PORT_BACK=8080
DELAI=90
ROLLBACK=1
SIMULATION=0

PREFIXE_IMAGE="orion-microcrm"
# Mémorise l'image précédemment déployée, par composant, pour le rollback.
declare -A IMAGE_PRECEDENTE=()

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--composant)
                COMPOSANT="${2:-}"
                valider_composant "$COMPOSANT" \
                    || mourir "composant invalide : « ${COMPOSANT:-vide} » (attendu : front, back ou tous)" 3
                shift 2 ;;
            -e|--environnement)
                ENVIRONNEMENT="${2:-}"
                valider_environnement "$ENVIRONNEMENT" \
                    || mourir "environnement invalide : « ${ENVIRONNEMENT:-vide} » (attendu : dev, staging ou prod)" 3
                shift 2 ;;
            --cible)
                CIBLE="${2:-}"
                [[ "$CIBLE" == "docker" || "$CIBLE" == "kubernetes" ]] \
                    || mourir "cible invalide : « ${CIBLE:-vide} » (attendu : docker ou kubernetes)" 3
                shift 2 ;;
            -V|--version)    VERSION="${2:?version requise}" ; shift 2 ;;
            -p|--port-front) PORT_FRONT="${2:?port requis}" ; shift 2 ;;
            -P|--port-back)  PORT_BACK="${2:?port requis}" ; shift 2 ;;
            -d|--delai)      DELAI="${2:?délai requis}" ; shift 2 ;;
            --sans-rollback) ROLLBACK=0 ; shift ;;
            -n|--simulation) SIMULATION=1 ; shift ;;
            -v|--verbeux)    export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)       afficher_aide ; exit 0 ;;
            *)               mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

# Le nom du conteneur inclut l'environnement : plusieurs environnements
# peuvent ainsi coexister sur une même machine sans collision.
nom_conteneur() { printf '%s-%s-%s\n' "$PREFIXE_IMAGE" "$1" "$ENVIRONNEMENT"; }
nom_image()     { printf '%s-%s:%s\n' "$PREFIXE_IMAGE" "$1" "$VERSION"; }

verifier_docker() {
    exiger_commandes docker
    docker info >/dev/null 2>&1 \
        || mourir "le démon Docker ne répond pas — démarrez Docker Desktop avant de déployer." 2
    log_debug "démon Docker opérationnel"
}

construire_image() {
    local composant="$1" racine="$2"
    local image ; image=$(nom_image "$composant")

    log_info "construction de l'image $image (étage « $composant »)"
    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] docker build --target $composant -t $image app/"
        return 0
    fi

    docker build \
        --target "$composant" \
        --tag "$image" \
        --label "org.opencontainers.image.version=$VERSION" \
        --label "org.opencontainers.image.revision=${COMMIT:-inconnu}" \
        --label "orion.environnement=$ENVIRONNEMENT" \
        "$racine/app" \
        || mourir "échec de la construction de l'image $composant" 1

    log_ok "image construite : $image"
}

demarrer_conteneur() {
    local composant="$1"
    local conteneur ; conteneur=$(nom_conteneur "$composant")
    local image     ; image=$(nom_image "$composant")

    # Mémorisation de l'image en place AVANT de l'arrêter : c'est cette
    # référence qui permet le rollback si le test de fumée échoue.
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$conteneur"; then
        local precedente
        precedente=$(docker inspect --format '{{.Config.Image}}' "$conteneur" 2>/dev/null || echo "")
        [[ -n "$precedente" ]] && IMAGE_PRECEDENTE["$composant"]="$precedente"
        log_info "état N-1 mémorisé pour $composant : ${precedente:-aucun}"

        if [[ $SIMULATION -eq 0 ]]; then
            docker rm -f "$conteneur" >/dev/null 2>&1 || true
        fi
    fi

    local port_hote port_conteneur
    if [[ "$composant" == "front" ]]; then
        port_hote="$PORT_FRONT" ; port_conteneur=80
    else
        port_hote="$PORT_BACK"  ; port_conteneur=8080
    fi

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] docker run -d --name $conteneur -p $port_hote:$port_conteneur $image"
        return 0
    fi

    docker run --detach \
        --name "$conteneur" \
        --publish "$port_hote:$port_conteneur" \
        --restart unless-stopped \
        --label "orion.environnement=$ENVIRONNEMENT" \
        --label "orion.version=$VERSION" \
        "$image" >/dev/null \
        || mourir "échec du démarrage du conteneur $conteneur" 1

    log_ok "conteneur démarré : $conteneur (port $port_hote)"
}

# Test de fumée : le service doit répondre dans le délai imparti.
# On sonde par paliers plutôt qu'une seule fois : une JVM Spring Boot met
# plusieurs secondes à démarrer, une vérification immédiate échouerait toujours.
test_de_fumee() {
    local composant="$1"
    local port ; [[ "$composant" == "front" ]] && port="$PORT_FRONT" || port="$PORT_BACK"
    local url="http://localhost:$port/"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] sonde de $url pendant $DELAI s"
        return 0
    fi

    log_info "test de fumée sur $url (délai max : ${DELAI}s)"
    local ecoule=0 intervalle=3
    while [[ $ecoule -lt $DELAI ]]; do
        if curl --silent --fail --max-time 5 --output /dev/null "$url" 2>/dev/null; then
            log_ok "$composant répond après ${ecoule}s"
            return 0
        fi
        sleep "$intervalle"
        ecoule=$((ecoule + intervalle))
        log_debug "…$composant ne répond pas encore (${ecoule}s)"
    done

    log_erreur "$composant n'a pas répondu dans le délai de ${DELAI}s"
    return 1
}

# Rollback : redémarre le conteneur sur l'image précédemment en place.
# C'est le pendant « Docker » de `helm rollback`, qui prendra le relais en
# phase 4 pour la cible Kubernetes.
effectuer_rollback() {
    local composant="$1"
    local conteneur ; conteneur=$(nom_conteneur "$composant")
    local precedente="${IMAGE_PRECEDENTE[$composant]:-}"

    if [[ -z "$precedente" ]]; then
        log_avert "aucun état N-1 connu pour $composant : rollback impossible (premier déploiement)"
        [[ $SIMULATION -eq 0 ]] && docker rm -f "$conteneur" >/dev/null 2>&1 || true
        return 1
    fi

    log_titre "ROLLBACK de $composant vers $precedente"
    docker rm -f "$conteneur" >/dev/null 2>&1 || true

    local port_hote port_conteneur
    if [[ "$composant" == "front" ]]; then
        port_hote="$PORT_FRONT" ; port_conteneur=80
    else
        port_hote="$PORT_BACK"  ; port_conteneur=8080
    fi

    docker run --detach --name "$conteneur" \
        --publish "$port_hote:$port_conteneur" \
        --restart unless-stopped \
        "$precedente" >/dev/null \
        || { log_erreur "le rollback de $composant a lui aussi échoué — intervention manuelle requise" ; return 1 ; }

    log_ok "rollback effectué : $composant restauré sur $precedente"
    return 0
}

deployer_docker() {
    local racine="$1"
    verifier_docker

    local -a composants=()
    mapfile -t composants < <(composants_de "$COMPOSANT")

    local composant
    for composant in "${composants[@]}"; do
        log_titre "Déploiement de $composant — environnement $ENVIRONNEMENT — version $VERSION"
        construire_image "$composant" "$racine"
        demarrer_conteneur "$composant"
    done

    local echec=0
    for composant in "${composants[@]}"; do
        if ! test_de_fumee "$composant"; then
            echec=1
            if [[ $ROLLBACK -eq 1 ]]; then
                effectuer_rollback "$composant" || true
            else
                log_avert "--sans-rollback : l'état en échec est conservé pour diagnostic"
            fi
        fi
    done

    if [[ $echec -eq 1 ]]; then
        resume_ci "Déploiement $ENVIRONNEMENT" "❌ échec du test de fumée (rollback effectué)"
        mourir "déploiement en échec — test de fumée non concluant." 6
    fi

    log_titre "Déploiement réussi"
    for composant in "${composants[@]}"; do
        local port ; [[ "$composant" == "front" ]] && port="$PORT_FRONT" || port="$PORT_BACK"
        log_ok "$composant → http://localhost:$port (image $(nom_image "$composant"))"
    done
    resume_ci "Déploiement $ENVIRONNEMENT" "✅ version $VERSION"
}

principal() {
    analyser_arguments "$@"

    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)

    COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "inconnu")
    # Sans version explicite, le SHA du commit fait foi : c'est l'identifiant
    # immuable recommandé par le plan de normalisation (docs/03, §2.3).
    [[ -n "$VERSION" ]] || VERSION="sha-$COMMIT"
    log_info "version déployée : $VERSION (commit $COMMIT)"

    case "$CIBLE" in
        docker)
            deployer_docker "$racine"
            ;;
        kubernetes)
            log_erreur "cible « kubernetes » : sera implémentée en phase 4 (charts Helm + helm rollback)."
            log_info  "Utilisez --cible docker pour un déploiement local immédiat."
            exit 7
            ;;
    esac

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"
}

principal "$@"
