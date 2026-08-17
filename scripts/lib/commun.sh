#!/usr/bin/env bash
# =============================================================================
# commun.sh — Bibliothèque de fonctions partagées par les scripts d'Orion
# =============================================================================
#
# BUT
#   Centraliser les fonctions utilisées par tous les scripts d'automatisation :
#   journalisation homogène, vérification des prérequis, validation des
#   paramètres et calculs de rétention des sauvegardes. Éviter la duplication
#   de code entre `install-deps.sh`, `run-tests.sh`, `deploy-build.sh` et
#   `backup.sh`, et concentrer en un seul endroit les fonctions critiques
#   couvertes par les tests `bash_unit`.
#
# FONCTIONNEMENT
#   Ce fichier n'est PAS exécutable : il est destiné à être sourcé.
#     source "$(dirname "$0")/lib/commun.sh"
#   Il n'exécute aucune action au chargement (aucun effet de bord), ce qui le
#   rend testable unitairement : `tests/test_commun.sh` le source et appelle
#   directement ses fonctions.
#
#   Les fonctions dites « pures » (aucune E/S, résultat déductible des seuls
#   arguments) sont marquées [PURE] : ce sont celles qui portent la logique
#   critique et qui sont couvertes par bash_unit.
#
# PARAMÈTRES
#   Aucun paramètre de ligne de commande. Variables d'environnement lues :
#     ORION_COULEUR   "0" pour désactiver la couleur (défaut : auto-détection)
#     ORION_VERBEUX   "1" pour activer les messages de débogage
#
# CONDITIONS D'EXÉCUTION
#   - Bash >= 4 (associatif non requis, mais `local -n` et `mapfile` utilisés)
#   - Aucun privilège particulier
#   - Aucune dépendance externe : uniquement des commandes POSIX de base
#   - Portable Linux (runners CI, conteneurs) et Git Bash sous Windows
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

# Garde d'inclusion : évite un double chargement si plusieurs scripts sourcent
# la bibliothèque dans la même session.
[[ -n "${ORION_COMMUN_CHARGE:-}" ]] && return 0
ORION_COMMUN_CHARGE=1

# -----------------------------------------------------------------------------
# Journalisation
# -----------------------------------------------------------------------------

# La couleur est désactivée automatiquement hors terminal (fichiers de log, CI),
# afin de ne pas polluer les journaux avec des séquences d'échappement.
if [[ "${ORION_COULEUR:-auto}" == "0" ]] || [[ ! -t 1 ]]; then
    _C_ROUGE="" ; _C_VERT="" ; _C_JAUNE="" ; _C_BLEU="" ; _C_GRIS="" ; _C_FIN=""
else
    _C_ROUGE=$'\033[0;31m' ; _C_VERT=$'\033[0;32m' ; _C_JAUNE=$'\033[0;33m'
    _C_BLEU=$'\033[0;34m'  ; _C_GRIS=$'\033[0;90m' ; _C_FIN=$'\033[0m'
fi

# Les messages informatifs partent sur stdout, les erreurs sur stderr :
# un appelant peut ainsi capturer la sortie utile sans les diagnostics.
log_info()   { printf '%s[INFO]%s  %s\n'  "$_C_BLEU"  "$_C_FIN" "$*"; }
log_ok()     { printf '%s[OK]%s    %s\n'  "$_C_VERT"  "$_C_FIN" "$*"; }
log_avert()  { printf '%s[AVERT]%s %s\n'  "$_C_JAUNE" "$_C_FIN" "$*" >&2; }
log_erreur() { printf '%s[ERREUR]%s %s\n' "$_C_ROUGE" "$_C_FIN" "$*" >&2; }
log_debug()  { [[ "${ORION_VERBEUX:-0}" == "1" ]] && printf '%s[DEBUG] %s%s\n' "$_C_GRIS" "$*" "$_C_FIN" >&2; return 0; }

# Titre de section, pour délimiter visuellement les étapes dans les logs CI.
log_titre() {
    printf '\n%s=== %s ===%s\n' "$_C_BLEU" "$*" "$_C_FIN"
}

# Interrompt le script avec un message et un code de sortie.
# Usage : mourir "message" [code]
mourir() {
    log_erreur "$1"
    exit "${2:-1}"
}

# -----------------------------------------------------------------------------
# Vérification des prérequis
# -----------------------------------------------------------------------------

# verifier_commande <nom> [message d'aide]
#   Vérifie qu'une commande est disponible dans le PATH.
#   Retourne 0 si présente, 1 sinon (n'interrompt pas : c'est à l'appelant de
#   décider si le prérequis est bloquant ou seulement souhaitable).
verifier_commande() {
    local cmd="$1"
    local aide="${2:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        log_debug "commande trouvée : $cmd"
        return 0
    fi
    log_erreur "commande introuvable : $cmd${aide:+ — $aide}"
    return 1
}

# exiger_commandes <cmd> [cmd...]
#   Variante bloquante : interrompt le script si l'une des commandes manque.
#   Toutes les commandes sont testées avant de sortir, afin d'afficher la liste
#   complète des manques plutôt que de les découvrir un par un.
exiger_commandes() {
    local manquantes=0
    for cmd in "$@"; do
        verifier_commande "$cmd" || manquantes=$((manquantes + 1))
    done
    [[ $manquantes -eq 0 ]] || mourir "$manquantes prérequis manquant(s) — installation requise avant exécution." 2
}

# -----------------------------------------------------------------------------
# Fonctions pures — couvertes par bash_unit (tests/test_commun.sh)
# -----------------------------------------------------------------------------

# [PURE] valider_composant <valeur>
#   Valide qu'un composant demandé fait partie des valeurs autorisées.
#   Les scripts acceptent tous le même vocabulaire : front | back | tous.
#   Retourne 0 si valide, 1 sinon. Aucune sortie sur stdout en cas de succès.
valider_composant() {
    case "${1:-}" in
        front|back|tous) return 0 ;;
        *) return 1 ;;
    esac
}

# [PURE] composants_de <valeur>
#   Convertit un composant demandé en liste effective, un par ligne.
#   « tous » se développe en « front back ». C'est la fonction qui permet aux
#   scripts de traiter uniformément un ou plusieurs composants.
composants_de() {
    case "${1:-}" in
        tous)  printf 'front\nback\n' ;;
        front) printf 'front\n' ;;
        back)  printf 'back\n' ;;
        *)     return 1 ;;
    esac
}

# [PURE] horodatage
#   Retourne un horodatage UTC au format AAAAMMJJ-HHMMSS.
#   UTC et non heure locale : les sauvegardes produites sur des machines de
#   fuseaux différents restent ainsi triables par ordre alphabétique, et le
#   changement d'heure ne crée pas deux archives de même nom.
horodatage() {
    date -u +'%Y%m%d-%H%M%S'
}

# [PURE] nom_archive <prefixe> <horodatage>
#   Construit le nom canonique d'une archive de sauvegarde.
#   Format : <prefixe>_<horodatage>.tar.gz
#   Centralisé ici car il est produit par `backup.sh` et *analysé* par la
#   fonction de purge : les deux doivent impérativement rester cohérents.
nom_archive() {
    local prefixe="${1:?prefixe requis}"
    local stamp="${2:?horodatage requis}"
    printf '%s_%s.tar.gz\n' "$prefixe" "$stamp"
}

# [PURE] archives_a_purger <retention> [fichier...]
#   Détermine quelles archives doivent être supprimées pour ne conserver que
#   les <retention> plus récentes. Les fichiers sont triés par nom : c'est
#   valide car `nom_archive` encode un horodatage UTC de longueur fixe, donc
#   l'ordre alphabétique est l'ordre chronologique.
#
#   Retourne sur stdout la liste des fichiers à supprimer (un par ligne).
#
#   ⚠️ Fonction critique : un défaut ici détruit des sauvegardes. Elle est
#   volontairement PURE (elle ne supprime rien, elle décide) afin d'être
#   testable exhaustivement par bash_unit — c'est `backup.sh` qui applique
#   la décision. Cette séparation décision/action est le cœur de sa sûreté.
#
#   Cas limites gérés : rétention <= 0 (ne purge rien, garde-fou contre une
#   variable vide ou mal typée), liste vide, moins d'archives que la rétention.
archives_a_purger() {
    local retention="${1:-0}"
    shift || true

    # Garde-fou : une rétention nulle, négative ou non numérique ne doit
    # JAMAIS être interprétée comme « tout supprimer ».
    if ! [[ "$retention" =~ ^[0-9]+$ ]] || [[ "$retention" -le 0 ]]; then
        return 0
    fi

    [[ $# -eq 0 ]] && return 0

    local -a triees
    mapfile -t triees < <(printf '%s\n' "$@" | sort)

    local total=${#triees[@]}
    [[ $total -le $retention ]] && return 0

    local a_supprimer=$((total - retention))
    local i
    for ((i = 0; i < a_supprimer; i++)); do
        printf '%s\n' "${triees[$i]}"
    done
}

# [PURE] attribut_xml <ligne> <nom>
#   Extrait la valeur numérique d'un attribut XML depuis une ligne de balise,
#   et retourne 0 lorsque l'attribut est ABSENT.
#
#   ⚠️ Ce comportement par défaut est le cœur de la fonction. Les producteurs
#   de rapports JUnit ne sont pas homogènes : Gradle émet `skipped="0"`, tandis
#   que karma-junit-reporter omet purement et simplement l'attribut. Une
#   extraction naïve renvoie alors une chaîne vide qui, injectée dans une
#   expression arithmétique, provoque « operand expected » et fait échouer le
#   job alors que TOUS les tests sont passés — défaut effectivement rencontré
#   sur le pipeline, d'où cette fonction et ses tests.
attribut_xml() {
    local ligne="${1:-}" nom="${2:-}" valeur
    valeur=$(sed -n "s/.*${nom}=\"\([0-9]*\)\".*/\1/p" <<<"$ligne" | head -1)
    printf '%s\n' "${valeur:-0}"
}

# [PURE] valider_environnement <valeur>
#   Valide un nom d'environnement de déploiement.
#   dev | staging | prod — alignés sur les values Helm (phase 4).
valider_environnement() {
    case "${1:-}" in
        dev|staging|prod) return 0 ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Utilitaires d'environnement
# -----------------------------------------------------------------------------

# racine_projet
#   Retourne la racine du dépôt. Utilise git quand c'est possible (fiable même
#   depuis un sous-répertoire), sinon remonte depuis l'emplacement du script.
#   Permet d'invoquer les scripts depuis n'importe quel répertoire courant.
racine_projet() {
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # shellcheck disable=SC2128  # BASH_SOURCE[0] suffit ici
        cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
    fi
}

# selectionner_chrome
#   Détermine le binaire Chrome/Chromium à utiliser pour les tests Karma et
#   l'exporte dans CHROME_BIN.
#
#   Pourquoi cette fonction : le pipeline d'origine codait en dur
#   `/opt/google/chrome/chrome` (chemin de l'image `cypress/browsers`). Ce
#   chemin n'existe ni sur un runner GitHub, ni sur un poste de développement,
#   ce qui rendait les tests front non exécutables en dehors d'une seule image.
#   La détection rend le script portable poste ↔ CI.
#
#   Retourne 0 si un binaire est trouvé (CHROME_BIN exporté), 1 sinon.
selectionner_chrome() {
    if [[ -n "${CHROME_BIN:-}" ]] && [[ -x "${CHROME_BIN}" ]]; then
        log_debug "CHROME_BIN déjà positionné : $CHROME_BIN"
        return 0
    fi

    local candidat
    for candidat in \
        /usr/bin/google-chrome \
        /usr/bin/google-chrome-stable \
        /usr/bin/chromium \
        /usr/bin/chromium-browser \
        /opt/google/chrome/chrome \
        "/c/Program Files/Google/Chrome/Application/chrome.exe"
    do
        if [[ -x "$candidat" ]]; then
            export CHROME_BIN="$candidat"
            log_debug "Chrome détecté : $CHROME_BIN"
            return 0
        fi
    done

    # Dernier recours : recherche dans le PATH.
    for candidat in google-chrome chromium chrome; do
        if command -v "$candidat" >/dev/null 2>&1; then
            CHROME_BIN="$(command -v "$candidat")"
            export CHROME_BIN
            log_debug "Chrome détecté via PATH : $CHROME_BIN"
            return 0
        fi
    done

    return 1
}

# duree_lisible <secondes>
#   Formate une durée en « 1m 23s » pour les rapports de fin d'exécution.
duree_lisible() {
    local s="${1:-0}"
    if [[ "$s" -lt 60 ]]; then
        printf '%ds\n' "$s"
    else
        printf '%dm %02ds\n' $((s / 60)) $((s % 60))
    fi
}

# resume_ci <clé> <valeur>
#   Ajoute une ligne au résumé de job GitHub Actions si le contexte le permet.
#   Sans effet hors CI : les scripts restent utilisables tels quels en local.
resume_ci() {
    [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
    printf '| %s | %s |\n' "$1" "$2" >> "$GITHUB_STEP_SUMMARY"
}
