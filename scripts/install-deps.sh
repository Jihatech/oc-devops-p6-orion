#!/usr/bin/env bash
# =============================================================================
# install-deps.sh — Installation des dépendances de l'application MicroCRM
# =============================================================================
#
# BUT
#   Installer de façon déterministe et reproductible les dépendances des deux
#   composants de l'application (frontend Angular et backend Spring Boot), que
#   ce soit sur un poste de développement ou sur un runner d'intégration
#   continue. Un seul point d'entrée remplace les commandes `npm ci` et
#   `gradlew` disséminées dans le pipeline et dans le README : le poste et la
#   CI exécutent ainsi rigoureusement la même procédure (parité dev/CI).
#
# FONCTIONNEMENT
#   1. Vérifie les prérequis du ou des composants demandés (npm, node / java).
#   2. Frontend : exécute `npm ci` — et non `npm install` — afin d'installer
#      EXACTEMENT les versions figées dans `package-lock.json`. C'est la
#      condition d'un build reproductible : `npm install` peut mettre à jour le
#      verrou et faire diverger silencieusement le poste de la CI.
#      Si le verrou est absent, le script échoue explicitement plutôt que de
#      basculer sur `npm install` en silence.
#   3. Backend : résout et met en cache les dépendances Gradle sans compiler
#      (`gradlew dependencies`), ce qui permet de séparer nettement l'échec
#      « dépendance indisponible » de l'échec « code qui ne compile pas ».
#   4. Affiche un récapitulatif (durée, composants traités) et alimente le
#      résumé de job GitHub Actions lorsqu'il est exécuté en CI.
#
# PARAMÈTRES
#   -c, --composant <front|back|tous>  Composant à traiter          (défaut : tous)
#   -o, --hors-ligne                   Mode hors ligne : utilise uniquement les
#                                      caches locaux (npm --offline,
#                                      gradlew --offline)
#   -v, --verbeux                      Journalisation détaillée
#   -h, --aide                         Affiche cette aide
#
#   Variables d'environnement lues :
#     ORION_VERBEUX=1   équivalent de --verbeux
#
# CONDITIONS D'EXÉCUTION
#   - Exécutable depuis n'importe quel répertoire (la racine du dépôt est
#     résolue automatiquement).
#   - Frontend : Node.js >= 18.13 et npm >= 9 ; `app/front/package-lock.json`
#     doit être présent et versionné.
#   - Backend  : JDK 17 minimum ; `app/back/gradlew` présent et exécutable.
#   - Accès réseau requis, sauf en mode --hors-ligne.
#   - Aucun privilège root nécessaire. Aucun secret manipulé.
#   - Codes de sortie : 0 succès · 1 erreur d'exécution · 2 prérequis manquant
#     · 3 paramètre invalide
#
# EXEMPLES
#   ./scripts/install-deps.sh                       # les deux composants
#   ./scripts/install-deps.sh --composant front     # frontend uniquement
#   ./scripts/install-deps.sh -c back --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

COMPOSANT="tous"
HORS_LIGNE=0

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
                shift 2
                ;;
            -o|--hors-ligne) HORS_LIGNE=1 ; shift ;;
            -v|--verbeux)    export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)       afficher_aide ; exit 0 ;;
            *)               mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

installer_front() {
    local racine="$1"
    local repertoire="$racine/app/front"

    log_titre "Frontend — installation des dépendances npm"
    exiger_commandes node npm

    [[ -f "$repertoire/package-lock.json" ]] \
        || mourir "package-lock.json absent : impossible de garantir un build reproductible. Exécutez 'npm install' puis versionnez le verrou." 1

    local -a options=(--no-audit --no-fund)
    [[ $HORS_LIGNE -eq 1 ]] && options+=(--offline)

    log_info "node $(node --version) / npm $(npm --version)"
    log_info "npm ci dans app/front (versions figées par le verrou)"

    ( cd "$repertoire" && npm ci "${options[@]}" ) \
        || mourir "échec de l'installation des dépendances frontend" 1

    local paquets
    paquets=$(find "$repertoire/node_modules" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
    log_ok "frontend : dépendances installées ($paquets paquets de premier niveau)"
    resume_ci "Dépendances frontend" "$paquets paquets"
}

installer_back() {
    local racine="$1"
    local repertoire="$racine/app/back"

    log_titre "Backend — résolution des dépendances Gradle"
    exiger_commandes java

    [[ -x "$repertoire/gradlew" ]] \
        || mourir "app/back/gradlew introuvable ou non exécutable" 1

    local -a options=(--console=plain --quiet)
    [[ $HORS_LIGNE -eq 1 ]] && options+=(--offline)

    log_info "java $(java -version 2>&1 | head -1 | cut -d'"' -f2)"
    log_info "résolution du classpath d'exécution (sans compilation)"

    ( cd "$repertoire" && ./gradlew dependencies --configuration runtimeClasspath "${options[@]}" >/dev/null ) \
        || mourir "échec de la résolution des dépendances backend" 1

    log_ok "backend : dépendances résolues et mises en cache"
    resume_ci "Dépendances backend" "classpath résolu"
}

principal() {
    analyser_arguments "$@"

    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)
    log_debug "racine du projet : $racine"

    local composant
    while read -r composant; do
        case "$composant" in
            front) installer_front "$racine" ;;
            back)  installer_back  "$racine" ;;
        esac
    done < <(composants_de "$COMPOSANT")

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"
}

principal "$@"
