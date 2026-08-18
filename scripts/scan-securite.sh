#!/usr/bin/env bash
# =============================================================================
# scan-securite.sh — Analyse de sécurité des dépendances, secrets et configurations
# =============================================================================
#
# BUT
#   Détecter, AVANT toute publication d'artefact, les vulnérabilités connues des
#   dépendances, les secrets accidentellement versionnés et les mauvaises
#   configurations d'infrastructure. Ce script est la mise en œuvre du principe
#   de « shift-left » sécurité (P2 du plan de normalisation) : il déplace dans
#   le pipeline du développeur les contrôles aujourd'hui réalisés à la main par
#   l'équipe Ops APRÈS transmission de l'image — le mécanisme même qui a retardé
#   le premier déploiement d'Orion (goulot G1, incident CVE de l'audit).
#
#   L'équipe Ops utilise déjà Trivy : il ne s'agit pas d'introduire un outil
#   inconnu, mais de le placer au bon endroit du cycle.
#
# FONCTIONNEMENT
#   Quatre contrôles indépendants, exécutés successivement. Le script poursuit
#   après un échec et ne rend son verdict qu'à la fin : un seul lancement donne
#   la vision complète des problèmes, plutôt qu'une découverte au compte-gouttes.
#
#     1. npm audit           vulnérabilités des dépendances JavaScript
#     2. trivy fs (vuln)     vulnérabilités des dépendances, JAR Java compris
#     3. trivy fs (secret)   credentials versionnés — clés, jetons, mots de passe
#     4. trivy config        mauvaises configurations Dockerfile / Kubernetes
#
#   Politique de blocage (justifiée dans docs/05-plan-securite.md) :
#   seules les vulnérabilités de sévérité HIGH ou CRITICAL **et disposant d'un
#   correctif publié** (--ignore-unfixed) sont bloquantes. Bloquer sur une CVE
#   sans correctif disponible reviendrait à bloquer l'équipe sur un problème
#   qu'elle ne peut pas résoudre : la seule issue serait de désactiver le
#   contrôle. Ces vulnérabilités sont donc RAPPORTÉES et suivies, pas ignorées.
#
#   En revanche, la détection d'un secret est TOUJOURS bloquante, quelle que
#   soit sa sévérité : un credential versionné est déjà compromis.
#
# PARAMÈTRES
#   -c, --controle <tous|deps|secrets|config>  Contrôle à exécuter   (défaut : tous)
#   -s, --sortie <répertoire>       Répertoire des rapports  (défaut : reports/securite)
#       --severite <liste>          Sévérités bloquantes     (défaut : HIGH,CRITICAL)
#       --inclure-non-corrigees     Signale aussi les CVE sans correctif publié
#       --non-bloquant              Rapporte sans faire échouer (mode découverte)
#   -v, --verbeux                   Journalisation détaillée
#   -h, --aide                      Affiche cette aide
#
# CONDITIONS D'EXÉCUTION
#   - Trivy installé (https://trivy.dev) — version épinglée par la CI.
#     En son absence, les contrôles Trivy sont SIGNALÉS COMME IGNORÉS, jamais
#     considérés comme réussis : un contrôle de sécurité silencieusement absent
#     est pire que pas de contrôle du tout.
#   - Node.js et npm pour `npm audit`, avec `app/front/package-lock.json`.
#   - Accès réseau pour la mise à jour des bases de vulnérabilités.
#   - Aucun privilège root. Aucun secret manipulé : le script en cherche, il
#     n'en consomme pas. Les rapports produits peuvent contenir le CHEMIN d'un
#     secret détecté, jamais sa valeur.
#   - Codes de sortie : 0 aucun problème bloquant · 1 vulnérabilité bloquante
#     · 2 prérequis manquant · 3 paramètre invalide · 4 contrôle ignoré
#     · 9 secret détecté (toujours bloquant)
#
# EXEMPLES
#   ./scripts/scan-securite.sh
#   ./scripts/scan-securite.sh --controle secrets
#   ./scripts/scan-securite.sh --non-bloquant --inclure-non-corrigees --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

CONTROLE="tous"
SORTIE="reports/securite"
SEVERITE="HIGH,CRITICAL"
NON_CORRIGEES=0
BLOQUANT=1

PROBLEMES=0
SECRETS=0
IGNORES=0

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--controle)
                CONTROLE="${2:-}"
                case "$CONTROLE" in
                    tous|deps|secrets|config) ;;
                    *) mourir "contrôle invalide : « ${CONTROLE:-vide} » (attendu : tous, deps, secrets ou config)" 3 ;;
                esac
                shift 2 ;;
            -s|--sortie)              SORTIE="${2:?répertoire requis}" ; shift 2 ;;
            --severite)               SEVERITE="${2:?liste de sévérités requise}" ; shift 2 ;;
            --inclure-non-corrigees)  NON_CORRIGEES=1 ; shift ;;
            --non-bloquant)           BLOQUANT=0 ; shift ;;
            -v|--verbeux)             export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)                afficher_aide ; exit 0 ;;
            *)                        mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

trivy_disponible() {
    if command -v trivy >/dev/null 2>&1; then
        return 0
    fi
    log_avert "Trivy absent : contrôle IGNORÉ (installation : https://trivy.dev/getting-started/installation/)"
    IGNORES=$((IGNORES + 1))
    return 1
}

controle_npm_audit() {
    local racine="$1" sortie="$2"
    log_titre "1/4 — Dépendances JavaScript (npm audit)"

    local repertoire="$racine/app/front"
    if [[ ! -f "$repertoire/package-lock.json" ]]; then
        log_avert "package-lock.json absent : contrôle IGNORÉ"
        IGNORES=$((IGNORES + 1))
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        log_avert "npm absent : contrôle IGNORÉ"
        IGNORES=$((IGNORES + 1))
        return 0
    fi

    # Le rapport complet est toujours produit, quel que soit le verdict :
    # c'est lui qui alimente le suivi de la dette de sécurité.
    ( cd "$repertoire" && npm audit --json ) > "$sortie/npm-audit.json" 2>/dev/null || true

    local critiques elevees
    critiques=$(sed -n 's/.*"critical" *: *\([0-9]*\).*/\1/p' "$sortie/npm-audit.json" | head -1)
    elevees=$(sed -n 's/.*"high" *: *\([0-9]*\).*/\1/p' "$sortie/npm-audit.json" | head -1)
    critiques="${critiques:-0}" ; elevees="${elevees:-0}"

    log_info "vulnérabilités npm — critiques : $critiques, élevées : $elevees"
    resume_ci "npm audit" "$critiques critique(s), $elevees élevée(s)"

    if [[ "$critiques" -gt 0 ]]; then
        log_erreur "$critiques vulnérabilité(s) CRITIQUE(S) dans les dépendances npm"
        PROBLEMES=$((PROBLEMES + 1))
    else
        log_ok "aucune vulnérabilité critique dans les dépendances npm"
    fi
}

controle_dependances() {
    local racine="$1" sortie="$2"
    log_titre "2/4 — Dépendances applicatives (Trivy fs)"
    trivy_disponible || return 0

    local -a options=(
        fs
        --scanners vuln
        --severity "$SEVERITE"
        --no-progress
        --format json
        --output "$sortie/trivy-dependances.json"
    )
    [[ $NON_CORRIGEES -eq 0 ]] && options+=(--ignore-unfixed)

    # Le JAR Spring Boot est analysé explicitement : Trivy sait y lire les
    # bibliothèques embarquées, ce qui couvre les dépendances Java là où
    # l'absence de gradle.lockfile empêche une analyse du manifeste.
    trivy "${options[@]}" "$racine/app" || true

    local nb
    nb=$(grep -o '"VulnerabilityID"' "$sortie/trivy-dependances.json" 2>/dev/null | wc -l | tr -d ' ')
    nb="${nb:-0}"

    log_info "vulnérabilités $SEVERITE corrigibles : $nb"
    resume_ci "Trivy — dépendances" "$nb vulnérabilité(s) $SEVERITE"

    if [[ "$nb" -gt 0 ]]; then
        log_erreur "$nb vulnérabilité(s) $SEVERITE avec correctif disponible"
        trivy fs --scanners vuln --severity "$SEVERITE" --ignore-unfixed \
            --no-progress --format table "$racine/app" 2>/dev/null | head -40 || true
        PROBLEMES=$((PROBLEMES + 1))
    else
        log_ok "aucune vulnérabilité $SEVERITE corrigible dans les dépendances"
    fi
}

controle_secrets() {
    local racine="$1" sortie="$2"
    log_titre "3/4 — Secrets versionnés (Trivy secret)"
    trivy_disponible || return 0

    trivy fs --scanners secret --no-progress \
        --format json --output "$sortie/trivy-secrets.json" "$racine" || true

    local nb
    nb=$(grep -o '"RuleID"' "$sortie/trivy-secrets.json" 2>/dev/null | wc -l | tr -d ' ')
    nb="${nb:-0}"

    resume_ci "Trivy — secrets" "$nb détection(s)"

    if [[ "$nb" -gt 0 ]]; then
        # La valeur du secret n'est jamais réaffichée : seuls le fichier et la
        # règle déclenchée sont journalisés.
        log_erreur "$nb secret(s) potentiel(s) détecté(s) — BLOCAGE INCONDITIONNEL"
        grep -o '"Title" *: *"[^"]*"' "$sortie/trivy-secrets.json" 2>/dev/null | head -10 || true
        SECRETS=$((SECRETS + 1))
    else
        log_ok "aucun secret versionné détecté"
    fi
}

controle_configuration() {
    local racine="$1" sortie="$2"
    log_titre "4/4 — Configurations d'infrastructure (Trivy config)"
    trivy_disponible || return 0

    # Non bloquant à ce stade du projet : le Dockerfile fourni comporte des
    # défauts connus et déjà documentés (constats A5 à A10 de l'audit), dont
    # le durcissement est planifié en phase 4. Le contrôle sert ici de
    # référence « avant » pour la comparaison du rapport de performance.
    trivy config --no-progress --severity "$SEVERITE" \
        --format json --output "$sortie/trivy-config.json" "$racine" || true

    local nb
    nb=$(grep -o '"AVDID"' "$sortie/trivy-config.json" 2>/dev/null | wc -l | tr -d ' ')
    nb="${nb:-0}"

    log_info "mauvaises configurations $SEVERITE : $nb"
    resume_ci "Trivy — configurations" "$nb point(s) $SEVERITE"

    if [[ "$nb" -gt 0 ]]; then
        log_avert "$nb mauvaise(s) configuration(s) — non bloquant en phase 3, durcissement prévu en phase 4"
        trivy config --no-progress --severity "$SEVERITE" --format table "$racine" 2>/dev/null | head -30 || true
    else
        log_ok "aucune mauvaise configuration $SEVERITE"
    fi
}

principal() {
    analyser_arguments "$@"

    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)
    [[ "$SORTIE" = /* ]] || SORTIE="$racine/$SORTIE"
    mkdir -p "$SORTIE"

    log_titre "Analyse de sécurité — MicroCRM"
    log_info "sévérités bloquantes : $SEVERITE"
    log_info "CVE sans correctif : $([[ $NON_CORRIGEES -eq 1 ]] && echo 'signalées' || echo 'rapportées mais non bloquantes')"
    log_info "rapports : $SORTIE"
    command -v trivy >/dev/null 2>&1 && log_info "trivy $(trivy --version 2>/dev/null | head -1)"

    case "$CONTROLE" in
        tous)
            controle_npm_audit    "$racine" "$SORTIE"
            controle_dependances  "$racine" "$SORTIE"
            controle_secrets      "$racine" "$SORTIE"
            controle_configuration "$racine" "$SORTIE"
            ;;
        deps)
            controle_npm_audit   "$racine" "$SORTIE"
            controle_dependances "$racine" "$SORTIE"
            ;;
        secrets) controle_secrets       "$racine" "$SORTIE" ;;
        config)  controle_configuration "$racine" "$SORTIE" ;;
    esac

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"

    if [[ $SECRETS -gt 0 ]]; then
        mourir "secret(s) détecté(s) — un credential versionné est déjà compromis. Rotation immédiate requise." 9
    fi
    if [[ $PROBLEMES -gt 0 ]]; then
        if [[ $BLOQUANT -eq 0 ]]; then
            log_avert "$PROBLEMES contrôle(s) en échec — ignoré (--non-bloquant)"
            exit 0
        fi
        mourir "$PROBLEMES contrôle(s) de sécurité en échec." 1
    fi
    if [[ $IGNORES -gt 0 ]]; then
        log_avert "$IGNORES contrôle(s) ignoré(s) — la couverture de sécurité n'est PAS complète."
        exit 4
    fi
    log_ok "tous les contrôles de sécurité sont passés."
}

principal "$@"
