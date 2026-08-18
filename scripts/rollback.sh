#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Retour à la version précédente d'un déploiement Helm
# =============================================================================
#
# BUT
#   Ramener une release Helm à sa révision précédente (ou à une révision
#   choisie), puis VÉRIFIER que le service répond effectivement avant de
#   déclarer le retour arrière réussi. Répond à la faiblesse f8 de l'audit —
#   Orion ne dispose aujourd'hui d'aucune procédure de retour arrière — et à
#   la question de soutenance annoncée : « en cas d'échec de déploiement,
#   quelle procédure de rollback et comment l'avez-vous automatisée ? ».
#
# FONCTIONNEMENT
#   1. Vérifie que la release existe et affiche son historique.
#   2. Détermine la révision cible : la dernière révision SAINE par défaut, ou
#      celle passée par --revision. Une révision en échec n'est jamais retenue
#      comme cible — ce serait revenir sur une version déjà cassée.
#   3. Exécute `helm rollback --wait` : Helm attend que les pods de la
#      révision restaurée soient prêts.
#   4. Vérifie l'état réel des pods, puis exécute un test de fumée HTTP via un
#      port-forward temporaire. Une release marquée « deployed » dont le
#      service ne répond pas n'est PAS un rollback réussi.
#   5. Écrit une trace horodatée de l'opération (option --preuves).
#
#   Un rollback Helm ne « défait » rien : il crée une NOUVELLE révision dont
#   le contenu est celui de la révision cible. L'historique reste donc complet
#   et auditable — point important pour la traçabilité (lacune S9 de l'audit).
#
# PARAMÈTRES
#   -r, --release <nom>        Nom de la release Helm          (défaut : microcrm)
#   -n, --namespace <nom>      Namespace Kubernetes            (défaut : orion-dev)
#   -R, --revision <n>         Révision cible                  (défaut : précédente saine)
#   -t, --delai <secondes>     Délai d'attente Helm            (défaut : 300)
#   -p, --port <n>             Port local du test de fumée     (défaut : 18099)
#       --sans-verification    N'exécute pas le test de fumée (diagnostic)
#   -P, --preuves <fichier>    Écrit une trace de l'opération
#   -N, --simulation           Affiche le plan sans rien exécuter
#   -v, --verbeux              Journalisation détaillée
#   -h, --aide                 Affiche cette aide
#
# CONDITIONS D'EXÉCUTION
#   - `helm` et `kubectl` installés, et un contexte Kubernetes actif pointant
#     vers le bon cluster (à vérifier : `kubectl config current-context`).
#   - Droits suffisants sur le namespace visé.
#   - La release doit compter AU MOINS DEUX révisions : on ne revient pas en
#     arrière depuis une première installation.
#   - Aucun secret manipulé. Aucun privilège root.
#   - Codes de sortie : 0 rollback vérifié · 1 échec du rollback
#     · 2 prérequis manquant · 3 paramètre invalide
#     · 6 rollback effectué mais service NON fonctionnel
#
# EXEMPLES
#   ./scripts/rollback.sh
#   ./scripts/rollback.sh --release microcrm --namespace orion-staging
#   ./scripts/rollback.sh --revision 3 --preuves docs/captures/rollback/trace.log
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

RELEASE="microcrm"
NAMESPACE="orion-dev"
REVISION=""
DELAI=300
PORT=18099
VERIFIER=1
PREUVES=""
SIMULATION=0

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release)         RELEASE="${2:?nom de release requis}" ; shift 2 ;;
            -n|--namespace)       NAMESPACE="${2:?namespace requis}" ; shift 2 ;;
            -R|--revision)
                REVISION="${2:-}"
                [[ "$REVISION" =~ ^[0-9]+$ ]] || mourir "révision invalide : « ${REVISION:-vide} » (entier attendu)" 3
                shift 2 ;;
            -t|--delai)           DELAI="${2:?délai requis}" ; shift 2 ;;
            -p|--port)            PORT="${2:?port requis}" ; shift 2 ;;
            --sans-verification)  VERIFIER=0 ; shift ;;
            -P|--preuves)         PREUVES="${2:?fichier de preuves requis}" ; shift 2 ;;
            -N|--simulation)      SIMULATION=1 ; shift ;;
            -v|--verbeux)         export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)            afficher_aide ; exit 0 ;;
            *)                    mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

trace() {
    [[ -n "$PREUVES" ]] || return 0
    printf '%s\n' "$*" >> "$PREUVES"
}

# Retourne la dernière révision SAINE, en excluant la révision courante.
# Une révision « failed » ne doit jamais servir de cible : revenir dessus
# restaurerait une version déjà défaillante.
revision_precedente_saine() {
    helm history "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null | python3 -c '
import json, sys
try:
    historique = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if len(historique) < 2:
    sys.exit(0)
saines = [r for r in historique[:-1] if r.get("status") in ("deployed", "superseded")]
print(saines[-1]["revision"] if saines else "")
' 2>/dev/null || true
}

etat_pods() {
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE" \
        -o custom-columns=NOM:.metadata.name,PRET:.status.containerStatuses[0].ready,ETAT:.status.phase,IMAGE:.spec.containers[0].image \
        --no-headers 2>/dev/null || true
}

test_de_fumee() {
    local service="$RELEASE-front"
    log_info "test de fumée sur le service $service"

    kubectl port-forward -n "$NAMESPACE" "svc/$service" "$PORT:8080" >/dev/null 2>&1 &
    local pf=$!
    # Laisse au tunnel le temps de s'établir avant la première requête.
    sleep 5

    local ok=0 ecoule=0
    while [[ $ecoule -lt 60 ]]; do
        if curl --silent --fail --max-time 5 --output /dev/null "http://localhost:$PORT/healthz" 2>/dev/null; then
            ok=1
            break
        fi
        sleep 3
        ecoule=$((ecoule + 3))
    done

    local api="indisponible"
    if [[ $ok -eq 1 ]] && curl --silent --fail --max-time 5 --output /dev/null "http://localhost:$PORT/api/persons" 2>/dev/null; then
        api="disponible"
    fi

    kill "$pf" 2>/dev/null || true
    wait "$pf" 2>/dev/null || true

    if [[ $ok -eq 1 ]]; then
        log_ok "service fonctionnel (frontend OK, API $api)"
        trace "  test de fumee : frontend OK, API $api"
        return 0
    fi
    log_erreur "le service ne répond pas après le rollback"
    trace "  test de fumee : ECHEC"
    return 1
}

principal() {
    analyser_arguments "$@"
    local debut ; debut=$(date +%s)

    exiger_commandes helm kubectl

    log_titre "Rollback — release « $RELEASE » (namespace $NAMESPACE)"

    helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 \
        || mourir "release « $RELEASE » introuvable dans le namespace « $NAMESPACE »" 1

    [[ -n "$PREUVES" ]] && mkdir -p "$(dirname "$PREUVES")"
    trace "===== ROLLBACK $(date -u +'%Y-%m-%dT%H:%M:%SZ') ====="
    trace "release=$RELEASE namespace=$NAMESPACE"

    log_info "historique de la release :"
    local historique
    historique=$(helm history "$RELEASE" -n "$NAMESPACE")
    printf '%s\n' "$historique" | sed 's/^/    /'
    trace "--- historique AVANT ---"
    trace "$historique"

    log_info "état AVANT rollback :"
    local avant
    avant=$(etat_pods)
    printf '%s\n' "$avant" | sed 's/^/    /'
    trace "--- pods AVANT ---"
    trace "$avant"

    local cible="$REVISION"
    if [[ -z "$cible" ]]; then
        cible=$(revision_precedente_saine)
        [[ -n "$cible" ]] \
            || mourir "aucune révision saine antérieure : impossible de revenir en arrière (une seule installation ?)" 1
        log_info "révision cible déduite : $cible (dernière révision saine)"
    else
        log_info "révision cible demandée : $cible"
    fi
    trace "revision cible : $cible"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] helm rollback $RELEASE $cible -n $NAMESPACE --wait"
        return 0
    fi

    log_titre "Exécution du rollback vers la révision $cible"
    if ! helm rollback "$RELEASE" "$cible" -n "$NAMESPACE" --wait --timeout "${DELAI}s" 2>&1 | sed 's/^/    /'; then
        trace "RESULTAT : ECHEC du helm rollback"
        mourir "le rollback Helm a échoué." 1
    fi

    log_ok "rollback Helm effectué"

    log_info "état APRÈS rollback :"
    local apres
    apres=$(etat_pods)
    printf '%s\n' "$apres" | sed 's/^/    /'
    trace "--- pods APRES ---"
    trace "$apres"

    local final
    final=$(helm history "$RELEASE" -n "$NAMESPACE")
    log_info "historique après rollback :"
    printf '%s\n' "$final" | tail -4 | sed 's/^/    /'
    trace "--- historique APRES ---"
    trace "$final"

    if [[ $VERIFIER -eq 1 ]]; then
        if ! test_de_fumee; then
            trace "RESULTAT : rollback effectue mais service NON fonctionnel"
            mourir "rollback effectué, mais le service ne répond pas — intervention manuelle requise." 6
        fi
    else
        log_avert "--sans-verification : le bon fonctionnement du service n'a PAS été contrôlé"
    fi

    local duree=$(( $(date +%s) - debut ))
    trace "RESULTAT : SUCCES en $(duree_lisible "$duree")"
    trace ""
    log_titre "Rollback vérifié en $(duree_lisible "$duree")"
    resume_ci "Rollback" "révision $cible restaurée et vérifiée"
}

principal "$@"
