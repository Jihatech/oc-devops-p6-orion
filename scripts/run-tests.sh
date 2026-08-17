#!/usr/bin/env bash
# =============================================================================
# run-tests.sh — Exécution des tests automatisés et production des rapports
# =============================================================================
#
# BUT
#   Exécuter la suite de tests des deux composants de MicroCRM et produire des
#   rapports exploitables : résultats JUnit XML et rapports de couverture aux
#   formats attendus par SonarQube (LCOV pour le frontend, JaCoCo XML pour le
#   backend). Le pipeline d'origine exécutait les tests sans jamais collecter
#   ni la couverture ni les rapports (constats C6 et C7 de l'audit) : ce script
#   comble ce manque et centralise les rapports dans un répertoire unique.
#
# FONCTIONNEMENT
#   1. Détecte le binaire Chrome nécessaire à Karma (`selectionner_chrome`).
#      Le pipeline d'origine codait en dur /opt/google/chrome/chrome, chemin
#      propre à une seule image Docker : les tests étaient donc inexécutables
#      ailleurs. La détection rend le script portable poste ↔ runner CI.
#   2. Frontend : `ng test` en mode non interactif, navigateur sans interface,
#      avec `--code-coverage` pour produire coverage/microcrm/lcov.info.
#   3. Backend : `gradlew test jacocoTestReport` — les résultats JUnit XML et
#      le rapport JaCoCo XML sont générés.
#   4. Copie tous les rapports dans <sortie>/ (défaut : reports/) selon une
#      arborescence stable, indépendante des conventions de chaque outil, afin
#      que la CI, SonarQube et l'archivage consomment des chemins constants.
#   5. Extrait un résumé chiffré (tests exécutés, échecs, couverture de lignes)
#      affiché en console et injecté dans le résumé de job GitHub Actions.
#
#   Le script poursuit l'exécution des deux composants même si le premier
#   échoue, puis sort en erreur à la fin : un seul lancement donne ainsi la
#   vision complète des échecs, au lieu d'un aller-retour par composant.
#
# PARAMÈTRES
#   -c, --composant <front|back|tous>  Composant à tester           (défaut : tous)
#   -s, --sortie <répertoire>          Répertoire des rapports      (défaut : reports)
#       --sans-couverture              Désactive la mesure de couverture
#                                      (exécution plus rapide en local)
#   -v, --verbeux                      Journalisation détaillée
#   -h, --aide                         Affiche cette aide
#
#   Variables d'environnement lues :
#     CHROME_BIN      Chemin explicite du navigateur (sinon auto-détection)
#     ORION_VERBEUX   1 pour activer le mode verbeux
#
# CONDITIONS D'EXÉCUTION
#   - Les dépendances doivent avoir été installées au préalable
#     (`./scripts/install-deps.sh`).
#   - Frontend : Chrome ou Chromium disponible sur la machine. En son absence,
#     le composant frontend est SIGNALÉ COMME IGNORÉ (et non silencieusement
#     réussi) : le script sort alors en code 4.
#   - Backend  : JDK 17 minimum.
#   - Aucun privilège root. Aucun secret manipulé. Aucun accès réseau requis
#     si les dépendances sont déjà en cache.
#   - Codes de sortie : 0 tous les tests passent · 1 au moins un test échoue
#     · 2 prérequis manquant · 3 paramètre invalide · 4 composant ignoré
#
# EXEMPLES
#   ./scripts/run-tests.sh
#   ./scripts/run-tests.sh --composant back --sortie /tmp/rapports
#   ./scripts/run-tests.sh -c front --sans-couverture
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

COMPOSANT="tous"
SORTIE="reports"
COUVERTURE=1

# Codes d'état cumulés par composant.
ECHECS=0
IGNORES=0

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
            -s|--sortie)        SORTIE="${2:?répertoire de sortie requis}" ; shift 2 ;;
            --sans-couverture)  COUVERTURE=0 ; shift ;;
            -v|--verbeux)       export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)          afficher_aide ; exit 0 ;;
            *)                  mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

tester_front() {
    local racine="$1" sortie="$2"
    local repertoire="$racine/app/front"

    log_titre "Frontend — tests Karma/Jasmine"
    exiger_commandes node npm

    if ! selectionner_chrome; then
        log_avert "aucun navigateur Chrome/Chromium détecté : tests frontend IGNORÉS."
        log_avert "Installez Chrome ou renseignez CHROME_BIN pour les exécuter."
        IGNORES=$((IGNORES + 1))
        resume_ci "Tests frontend" "⚠️ ignorés (Chrome absent)"
        return 0
    fi
    log_info "navigateur : $CHROME_BIN"

    [[ -d "$repertoire/node_modules" ]] \
        || mourir "dépendances frontend absentes — exécutez ./scripts/install-deps.sh -c front" 2

    local -a options=(
        test
        --no-watch
        --no-progress
        --browsers=ChromeHeadlessNoSandbox
    )
    [[ $COUVERTURE -eq 1 ]] && options+=(--code-coverage)

    local code=0
    ( cd "$repertoire" && npx --no-install ng "${options[@]}" ) || code=$?

    # Les rapports sont collectés même en cas d'échec : ce sont eux qui
    # permettent de diagnostiquer, il serait absurde de les perdre.
    mkdir -p "$sortie/front"
    if [[ -f "$repertoire/coverage/microcrm/lcov.info" ]]; then
        cp "$repertoire/coverage/microcrm/lcov.info" "$sortie/front/lcov.info"
        log_ok "couverture frontend collectée : $sortie/front/lcov.info"
    elif [[ $COUVERTURE -eq 1 ]]; then
        log_avert "rapport LCOV introuvable — la couverture ne sera pas remontée à SonarQube"
    fi

    if [[ $code -ne 0 ]]; then
        log_erreur "frontend : échec des tests (code $code)"
        ECHECS=$((ECHECS + 1))
        resume_ci "Tests frontend" "❌ échec"
    else
        log_ok "frontend : tests réussis"
        resume_ci "Tests frontend" "✅ réussis"
    fi
}

tester_back() {
    local racine="$1" sortie="$2"
    local repertoire="$racine/app/back"

    log_titre "Backend — tests JUnit"
    exiger_commandes java
    [[ -x "$repertoire/gradlew" ]] || mourir "app/back/gradlew introuvable" 2

    local -a taches=(test)
    [[ $COUVERTURE -eq 1 ]] && taches+=(jacocoTestReport)

    local code=0
    ( cd "$repertoire" && ./gradlew "${taches[@]}" --console=plain ) || code=$?

    mkdir -p "$sortie/back"
    if [[ -d "$repertoire/build/test-results/test" ]]; then
        cp -r "$repertoire/build/test-results/test/." "$sortie/back/junit/" 2>/dev/null || true
    fi
    if [[ -f "$repertoire/build/reports/jacoco/test/jacocoTestReport.xml" ]]; then
        cp "$repertoire/build/reports/jacoco/test/jacocoTestReport.xml" "$sortie/back/jacoco.xml"
        log_ok "couverture backend collectée : $sortie/back/jacoco.xml"
    elif [[ $COUVERTURE -eq 1 ]]; then
        log_avert "rapport JaCoCo introuvable — vérifiez le greffon jacoco dans build.gradle"
    fi

    if [[ $code -ne 0 ]]; then
        log_erreur "backend : échec des tests (code $code)"
        ECHECS=$((ECHECS + 1))
        resume_ci "Tests backend" "❌ échec"
    else
        log_ok "backend : tests réussis"
        resume_ci "Tests backend" "✅ réussis"
    fi
}

# Agrège les résultats JUnit XML du backend pour un affichage chiffré.
# Volontairement tolérant : un résumé indisponible ne doit jamais faire
# échouer une exécution dont les tests, eux, sont passés.
resumer_junit() {
    local repertoire="$1"
    [[ -d "$repertoire" ]] || return 0

    local total=0 echecs=0 erreurs=0 ignores=0 fichier
    while IFS= read -r fichier; do
        local ligne
        ligne=$(grep -o '<testsuite [^>]*' "$fichier" 2>/dev/null | head -1) || continue
        total=$((total   + $(sed -n 's/.*tests="\([0-9]*\)".*/\1/p'    <<<"$ligne" || echo 0)))
        echecs=$((echecs + $(sed -n 's/.*failures="\([0-9]*\)".*/\1/p' <<<"$ligne" || echo 0)))
        erreurs=$((erreurs + $(sed -n 's/.*errors="\([0-9]*\)".*/\1/p' <<<"$ligne" || echo 0)))
        ignores=$((ignores + $(sed -n 's/.*skipped="\([0-9]*\)".*/\1/p' <<<"$ligne" || echo 0)))
    done < <(find "$repertoire" -name 'TEST-*.xml' 2>/dev/null)

    [[ $total -eq 0 ]] && return 0
    log_info "backend : $total test(s) — $echecs échec(s), $erreurs erreur(s), $ignores ignoré(s)"
    resume_ci "Tests backend (détail)" "$total exécutés, $echecs échec(s)"
}

principal() {
    analyser_arguments "$@"

    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)

    # Chemin de sortie absolu : les sous-shells changent de répertoire.
    [[ "$SORTIE" = /* ]] || SORTIE="$racine/$SORTIE"
    mkdir -p "$SORTIE"
    log_info "rapports collectés dans : $SORTIE"

    local composant
    while read -r composant; do
        case "$composant" in
            front) tester_front "$racine" "$SORTIE" ;;
            back)  tester_back  "$racine" "$SORTIE" ;;
        esac
    done < <(composants_de "$COMPOSANT")

    resumer_junit "$SORTIE/back/junit"

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"

    if [[ $ECHECS -gt 0 ]]; then
        mourir "$ECHECS composant(s) en échec." 1
    fi
    if [[ $IGNORES -gt 0 ]]; then
        log_avert "$IGNORES composant(s) ignoré(s) — la suite n'est pas complète."
        exit 4
    fi
    log_ok "tous les tests sont passés."
}

principal "$@"
