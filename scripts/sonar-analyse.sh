#!/usr/bin/env bash
# =============================================================================
# sonar-analyse.sh — Analyse statique SonarQube de l'application MicroCRM
# =============================================================================
#
# BUT
#   Exécuter une analyse SonarQube complète du monorepo (SAST, security
#   hotspots, couverture, dette technique) contre un serveur SonarQube
#   Community, puis exploiter la quality gate comme porte bloquante du
#   pipeline. Répond à l'exigence non négociable de la mission (« SonarQube
#   obligatoire ») et à la demande explicite de l'équipe Dev dans le sondage :
#   disposer d'outils d'analyse statique pour ne pas introduire de mauvaises
#   pratiques, sur une stack Java où elle se déclare Débutante.
#
# FONCTIONNEMENT
#   1. Démarre (option --demarrer) un serveur SonarQube Community en conteneur,
#      ou se connecte à un serveur déjà en écoute (--url).
#   2. Attend que le serveur réponde « UP » sur /api/system/status. L'attente
#      est indispensable : Elasticsearch met plusieurs dizaines de secondes à
#      s'initialiser, et un scanner lancé trop tôt échoue sans diagnostic clair.
#   3. Initialise le compte administrateur : le mot de passe par défaut est
#      remplacé par un mot de passe ALÉATOIRE généré à l'exécution, puis un
#      jeton d'analyse est émis. Ni l'un ni l'autre n'est versionné, journalisé
#      ni réutilisé d'une exécution à l'autre.
#   4. Lance sonar-scanner-cli (version épinglée) sur la configuration décrite
#      dans `sonar-project.properties`.
#   5. Délègue à `scripts/sonar-report.py` l'attente de fin d'analyse, le
#      verdict de la quality gate et l'export des preuves (issues, security
#      hotspots, mesures) au format JSON et Markdown.
#   6. Arrête le serveur (option --arreter) et propage le verdict : le script
#      sort en erreur si la quality gate échoue.
#
# PARAMÈTRES
#   -u, --url <url>          URL du serveur SonarQube    (défaut : http://localhost:9000)
#   -d, --demarrer           Démarre un serveur en conteneur Docker
#   -a, --arreter            Arrête et supprime le conteneur en fin d'exécution
#   -V, --version <tag>      Image SonarQube             (défaut : voir SONAR_IMAGE)
#   -t, --delai <secondes>   Délai max de démarrage      (défaut : 300)
#   -s, --sortie <rép.>      Répertoire des preuves      (défaut : docs/captures/sonarqube)
#       --sans-gate          N'échoue pas si la quality gate échoue (diagnostic)
#   -n, --simulation         Affiche le plan sans rien exécuter
#   -v, --verbeux            Journalisation détaillée
#   -h, --aide               Affiche cette aide
#
#   Variables d'environnement lues :
#     SONAR_IMAGE          image et tag du serveur SonarQube
#     SONAR_SCANNER_IMAGE  image et tag du scanner
#     SONAR_TOKEN          jeton existant ; si fourni, l'initialisation du
#                          compte administrateur est ignorée
#
# CONDITIONS D'EXÉCUTION
#   - Docker installé et démon démarré (obligatoire avec --demarrer).
#   - curl et python3 disponibles.
#   - Le backend doit avoir été COMPILÉ au préalable (`./gradlew classes
#     testClasses`) : sans les classes, l'analyseur Java se limite à une lecture
#     syntaxique et ne détecte ni vulnérabilités ni security hotspots.
#   - Les rapports de couverture doivent être présents dans `reports/`
#     (`./scripts/run-tests.sh`), sinon la couverture remontera à 0 %.
#   - Mémoire : SonarQube embarque Elasticsearch et demande ~2 Go de RAM.
#     Le paramètre noyau `vm.max_map_count` doit valoir au moins 262144.
#   - Aucun secret n'est versionné : le mot de passe administrateur est généré
#     à l'exécution et le jeton est éphémère.
#   - Codes de sortie : 0 quality gate passée · 1 erreur d'exécution
#     · 2 prérequis manquant · 3 paramètre invalide · 8 quality gate en échec
#
# EXEMPLES
#   ./scripts/sonar-analyse.sh --demarrer --arreter
#   ./scripts/sonar-analyse.sh --url http://localhost:9000        # serveur déjà lancé
#   ./scripts/sonar-analyse.sh --demarrer --sans-gate --verbeux   # diagnostic
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

URL="http://localhost:9000"
DEMARRER=0
ARRETER=0
DELAI=300
SORTIE="docs/captures/sonarqube"
SANS_GATE=0
SIMULATION=0

# Versions épinglées (principe P5 de docs/03) : une image « latest » ferait
# varier le verdict de la quality gate sans aucun changement de code.
SONAR_IMAGE="${SONAR_IMAGE:-sonarqube:25.12.0.117093-community}"
SONAR_SCANNER_IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:12.1.0.3233_8.0.1}"
CONTENEUR="orion-sonarqube"

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--url)        URL="${2:?url requise}" ; shift 2 ;;
            -d|--demarrer)   DEMARRER=1 ; shift ;;
            -a|--arreter)    ARRETER=1 ; shift ;;
            -V|--version)    SONAR_IMAGE="sonarqube:${2:?tag requis}" ; shift 2 ;;
            -t|--delai)
                DELAI="${2:-}"
                [[ "$DELAI" =~ ^[0-9]+$ ]] || mourir "délai invalide : « ${DELAI:-vide} »" 3
                shift 2 ;;
            -s|--sortie)     SORTIE="${2:?répertoire requis}" ; shift 2 ;;
            --sans-gate)     SANS_GATE=1 ; shift ;;
            -n|--simulation) SIMULATION=1 ; shift ;;
            -v|--verbeux)    export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)       afficher_aide ; exit 0 ;;
            *)               mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

# Nettoyage systématique : sans ce piège, un échec en cours d'analyse
# laisserait un conteneur SonarQube orphelin sur la machine.
nettoyer() {
    if [[ $ARRETER -eq 1 ]] && [[ $SIMULATION -eq 0 ]]; then
        log_info "arrêt du serveur SonarQube"
        docker rm -f "$CONTENEUR" >/dev/null 2>&1 || true
    fi
}

demarrer_serveur() {
    exiger_commandes docker
    docker info >/dev/null 2>&1 || mourir "le démon Docker ne répond pas." 2

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] docker run -d --name $CONTENEUR -p 9000:9000 $SONAR_IMAGE"
        return 0
    fi

    docker rm -f "$CONTENEUR" >/dev/null 2>&1 || true

    log_info "démarrage de $SONAR_IMAGE"
    # SONAR_ES_BOOTSTRAP_CHECKS_DISABLE : le contrôle de démarrage
    # d'Elasticsearch est inadapté à un conteneur éphémère de CI, où les
    # limites noyau ne sont pas toujours ajustables.
    docker run --detach \
        --name "$CONTENEUR" \
        --publish 9000:9000 \
        --env SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
        "$SONAR_IMAGE" >/dev/null \
        || mourir "échec du démarrage du conteneur SonarQube" 1

    trap nettoyer EXIT
}

attendre_serveur() {
    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] attente de $URL/api/system/status"
        return 0
    fi

    log_info "attente du démarrage de SonarQube (délai max : ${DELAI}s)…"
    local ecoule=0 intervalle=5 statut
    while [[ $ecoule -lt $DELAI ]]; do
        statut=$(curl -sS --max-time 5 "$URL/api/system/status" 2>/dev/null \
                 | sed -n 's/.*"status" *: *"\([A-Z]*\)".*/\1/p' || true)
        if [[ "$statut" == "UP" ]]; then
            log_ok "SonarQube opérationnel après ${ecoule}s"
            return 0
        fi
        log_debug "…statut « ${statut:-injoignable} » (${ecoule}s)"
        sleep "$intervalle"
        ecoule=$((ecoule + intervalle))
    done

    log_erreur "SonarQube n'a pas démarré dans le délai de ${DELAI}s"
    [[ $DEMARRER -eq 1 ]] && docker logs --tail 40 "$CONTENEUR" 2>&1 | sed 's/^/    /' || true
    return 1
}

# Remplace le mot de passe par défaut par un mot de passe aléatoire, puis émet
# un jeton d'analyse. Le mot de passe par défaut d'un serveur SonarQube est
# public : le laisser en place, même sur un serveur éphémère, serait
# exactement le type de mauvaise pratique que ce projet vise à éliminer.
initialiser_compte() {
    if [[ -n "${SONAR_TOKEN:-}" ]]; then
        log_info "jeton fourni par l'environnement : initialisation ignorée"
        return 0
    fi
    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] rotation du mot de passe admin puis génération d'un jeton"
        SONAR_TOKEN="jeton-simule"
        return 0
    fi

    local nouveau
    nouveau="Ci-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')-A1"

    log_info "rotation du mot de passe administrateur par défaut"
    curl -sS -u "admin:admin" -X POST \
        --data-urlencode "login=admin" \
        --data-urlencode "password=$nouveau" \
        --data-urlencode "previousPassword=admin" \
        "$URL/api/users/change_password" >/dev/null 2>&1 || {
            log_avert "rotation impossible (mot de passe peut-être déjà modifié) — poursuite"
        }

    log_info "génération d'un jeton d'analyse éphémère"
    local reponse
    reponse=$(curl -sS -u "admin:$nouveau" -X POST \
        --data-urlencode "name=ci-$(date -u +%s)" \
        "$URL/api/user_tokens/generate" 2>/dev/null || true)

    SONAR_TOKEN=$(sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p' <<<"$reponse")
    [[ -n "$SONAR_TOKEN" ]] || mourir "impossible d'obtenir un jeton d'analyse SonarQube" 1

    export SONAR_TOKEN
    # Masquage explicite dans les journaux GitHub Actions : même éphémère, un
    # jeton ne doit jamais apparaître en clair dans une sortie conservée.
    [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$SONAR_TOKEN"
    log_ok "jeton d'analyse obtenu (valeur masquée)"
}

lancer_scanner() {
    local racine="$1"
    log_titre "Analyse statique du monorepo"

    [[ -d "$racine/app/back/build/classes" ]] \
        || log_avert "classes Java absentes : les vulnérabilités et hotspots Java NE seront PAS détectés (exécutez ./gradlew classes testClasses)"
    [[ -f "$racine/reports/back/jacoco.xml" ]] \
        || log_avert "rapport JaCoCo absent : la couverture backend remontera à 0 %"
    [[ -f "$racine/reports/front/lcov.info" ]] \
        || log_avert "rapport LCOV absent : la couverture frontend remontera à 0 %"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] $SONAR_SCANNER_IMAGE sur $URL"
        return 0
    fi

    exiger_commandes docker
    # --network host : le scanner s'exécute dans un conteneur et doit joindre
    # le serveur publié sur l'hôte.
    docker run --rm \
        --network host \
        --volume "$racine:/usr/src" \
        --env SONAR_HOST_URL="$URL" \
        --env SONAR_TOKEN="$SONAR_TOKEN" \
        "$SONAR_SCANNER_IMAGE" \
        || mourir "échec de l'exécution du scanner SonarQube" 1

    log_ok "analyse transmise au serveur"
}

principal() {
    analyser_arguments "$@"

    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)
    [[ "$SORTIE" = /* ]] || SORTIE="$racine/$SORTIE"

    exiger_commandes curl python3

    log_titre "SonarQube — analyse de MicroCRM"
    log_info "serveur   : $URL"
    log_info "image     : $SONAR_IMAGE"
    log_info "scanner   : $SONAR_SCANNER_IMAGE"
    log_info "preuves   : $SORTIE"

    [[ $DEMARRER -eq 1 ]] && demarrer_serveur
    attendre_serveur || mourir "serveur SonarQube indisponible" 1
    initialiser_compte
    lancer_scanner "$racine"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] export des preuves et verdict de la quality gate"
        return 0
    fi

    # L'analyse est traitée de façon asynchrone par le serveur : le rapport
    # d'exécution du scanner porte l'identifiant de la tâche à suivre.
    local rapport="$racine/.scannerwork/report-task.txt"
    local -a options=(--url "$URL" --sortie "$SORTIE")

    # La clé de projet est lue dans sonar-project.properties et transmise
    # explicitement. Sans cela, le script dépendrait entièrement de
    # `.scannerwork/report-task.txt` — un fichier écrit par le conteneur du
    # scanner, dont la présence et les droits ne sont pas garantis. C'est
    # précisément ce qui a fait échouer la première exécution alors que
    # l'analyse, elle, avait parfaitement réussi.
    local cle
    cle=$(sed -n 's/^sonar\.projectKey=//p' "$racine/sonar-project.properties" | head -1)
    [[ -n "$cle" ]] && options+=(--cle "$cle")

    if [[ -f "$rapport" ]]; then
        options+=(--rapport-tache "$rapport")
        log_debug "rapport de tâche trouvé : $rapport"
    else
        log_avert "rapport de tâche absent : suivi de l'analyse par interrogation du projet"
    fi
    [[ $SANS_GATE -eq 1 ]] && options+=(--sans-gate)

    local code=0
    SONAR_TOKEN="$SONAR_TOKEN" python3 "$racine/scripts/sonar-report.py" "${options[@]}" || code=$?

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"

    [[ $code -eq 0 ]] || exit "$code"
}

principal "$@"
