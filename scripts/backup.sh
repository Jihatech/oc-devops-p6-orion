#!/usr/bin/env bash
# =============================================================================
# backup.sh — Sauvegarde et restauration des artefacts et configurations
# =============================================================================
#
# BUT
#   Produire une sauvegarde horodatée, vérifiable et purgeable des éléments
#   nécessaires à la reconstruction d'un environnement MicroCRM : artefacts de
#   build (JAR et bundle Angular), configurations d'infrastructure (Helm,
#   Terraform, Ansible, ELK), définition du pipeline, et données applicatives
#   lorsqu'un volume est fourni. Répond à la faiblesse f8 de l'audit — aucune
#   sauvegarde ni procédure de restauration n'existe aujourd'hui chez Orion —
#   et à l'exigence de livrable « scripts d'automatisation (… back-up) ».
#
#   Le script assure les DEUX sens de l'opération : sauvegarder (--mode
#   sauvegarde) et restaurer (--mode restauration). Une sauvegarde qui n'a
#   jamais été restaurée n'est pas une sauvegarde : c'est une hypothèse.
#
# FONCTIONNEMENT
#   Mode « sauvegarde » (défaut) :
#     1. Vérifie que les sources existent ; ignore avec avertissement celles qui
#        sont absentes (un projet en cours de construction n'a pas encore tous
#        ses répertoires) et échoue si AUCUNE source n'est présente.
#     2. Crée une archive tar.gz nommée <prefixe>_<AAAAMMJJ-HHMMSS>.tar.gz,
#        horodatée en UTC pour rester triable entre machines.
#     3. Calcule une empreinte SHA-256 stockée à côté de l'archive (.sha256),
#        puis VÉRIFIE immédiatement l'archive relue : une archive corrompue est
#        détectée à la création, pas le jour de la restauration.
#     4. Écrit un manifeste JSON (contenu, versions, commit Git, taille) qui
#        rend la sauvegarde auto-descriptive.
#     5. Purge les archives excédentaires selon la rétention demandée, via la
#        fonction PURE `archives_a_purger` (couverte par bash_unit) : la
#        décision de suppression est testée unitairement, séparément de son
#        exécution.
#
#   Mode « restauration » :
#     1. Vérifie l'empreinte SHA-256 avant toute écriture — une archive
#        altérée est refusée.
#     2. Extrait dans le répertoire cible ; exige --forcer si celui-ci n'est
#        pas vide, afin de ne jamais écraser un état existant par accident.
#
# PARAMÈTRES
#   -m, --mode <sauvegarde|restauration>  Sens de l'opération   (défaut : sauvegarde)
#   -s, --source <chemin>       Source supplémentaire à sauvegarder ; répétable.
#                               Si aucune n'est fournie, l'ensemble par défaut
#                               est utilisé (voir CONTENU PAR DÉFAUT).
#   -d, --destination <rép.>    Répertoire des archives         (défaut : backups)
#   -p, --prefixe <nom>         Préfixe du nom d'archive        (défaut : microcrm)
#   -r, --retention <n>         Nombre d'archives conservées    (défaut : 7)
#                               0 ou valeur invalide = aucune purge (garde-fou)
#   -a, --archive <fichier>     Archive à restaurer (mode restauration, requis)
#   -t, --cible <répertoire>    Répertoire de restauration      (défaut : ./restauration)
#   -f, --forcer                Autorise l'écriture dans une cible non vide
#   -n, --simulation            N'écrit rien : affiche les actions prévues
#   -v, --verbeux               Journalisation détaillée
#   -h, --aide                  Affiche cette aide
#
# CONTENU PAR DÉFAUT DE LA SAUVEGARDE
#   app/back/build/libs   artefacts JAR         (s'ils existent)
#   app/front/dist        bundle Angular        (s'il existe)
#   helm/                 charts et values
#   terraform/            code d'infrastructure
#   ansible/              playbooks
#   elk/                  configuration de journalisation
#   .github/workflows/    définition du pipeline
#   docs/                 documentation du projet
#   ⚠️ Aucun secret n'est jamais inclus : les chemins sensibles (.env, *.key,
#      *.pem, kubeconfig, node_modules, .terraform, .git) sont explicitement
#      exclus de l'archive.
#
# CONDITIONS D'EXÉCUTION
#   - Commandes requises : tar, gzip, et sha256sum ou shasum.
#   - Droits d'écriture sur le répertoire de destination.
#   - Espace disque suffisant (une archive complète pèse quelques dizaines de Mo,
#     le JAR Spring Boot représentant l'essentiel du volume).
#   - Aucun privilège root. Aucun secret manipulé ni journalisé.
#   - Exécutable en local, en CI (tâche planifiée) ou depuis un playbook Ansible.
#   - Codes de sortie : 0 succès · 1 erreur d'exécution · 2 prérequis manquant
#     · 3 paramètre invalide · 5 vérification d'intégrité en échec
#
# EXEMPLES
#   ./scripts/backup.sh
#   ./scripts/backup.sh --retention 14 --destination /var/backups/microcrm
#   ./scripts/backup.sh --simulation --verbeux
#   ./scripts/backup.sh --mode restauration \
#       --archive backups/microcrm_20260817-020000.tar.gz --cible /tmp/restaure
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/lib/commun.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/commun.sh"

MODE="sauvegarde"
DESTINATION="backups"
PREFIXE="microcrm"
RETENTION=7
ARCHIVE=""
CIBLE="restauration"
FORCER=0
SIMULATION=0
declare -a SOURCES=()

# Chemins systématiquement exclus : secrets, caches et état local.
# C'est ici que se joue l'exigence « aucune donnée sensible exposée ».
declare -a EXCLUSIONS=(
    '--exclude=.git'
    '--exclude=node_modules'
    '--exclude=.terraform'
    '--exclude=*.tfstate*'
    '--exclude=.env'
    '--exclude=.env.*'
    '--exclude=*.key'
    '--exclude=*.pem'
    '--exclude=*.p12'
    '--exclude=kubeconfig'
    '--exclude=secrets.yaml'
)

afficher_aide() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

analyser_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mode)
                MODE="${2:-}"
                [[ "$MODE" == "sauvegarde" || "$MODE" == "restauration" ]] \
                    || mourir "mode invalide : « ${MODE:-vide} » (attendu : sauvegarde ou restauration)" 3
                shift 2 ;;
            -s|--source)      SOURCES+=("${2:?chemin source requis}") ; shift 2 ;;
            -d|--destination) DESTINATION="${2:?répertoire requis}" ; shift 2 ;;
            -p|--prefixe)     PREFIXE="${2:?préfixe requis}" ; shift 2 ;;
            -r|--retention)
                RETENTION="${2:-}"
                [[ "$RETENTION" =~ ^[0-9]+$ ]] || mourir "rétention invalide : « ${RETENTION:-vide} » (entier attendu)" 3
                shift 2 ;;
            -a|--archive)     ARCHIVE="${2:?chemin de larchive requis}" ; shift 2 ;;
            -t|--cible)       CIBLE="${2:?répertoire cible requis}" ; shift 2 ;;
            -f|--forcer)      FORCER=1 ; shift ;;
            -n|--simulation)  SIMULATION=1 ; shift ;;
            -v|--verbeux)     export ORION_VERBEUX=1 ; shift ;;
            -h|--aide)        afficher_aide ; exit 0 ;;
            *)                mourir "paramètre inconnu : $1 (voir --aide)" 3 ;;
        esac
    done
}

# Encapsule le calcul d'empreinte : sha256sum sous Linux, shasum sous macOS.
empreinte_sha256() {
    local fichier="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$fichier" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$fichier" | awk '{print $1}'
    else
        mourir "ni sha256sum ni shasum disponible : impossible de garantir l'intégrité" 2
    fi
}

sources_par_defaut() {
    printf '%s\n' \
        'app/back/build/libs' \
        'app/front/dist' \
        'helm' \
        'terraform' \
        'ansible' \
        'elk' \
        '.github/workflows' \
        'docs'
}

ecrire_manifeste() {
    local fichier="$1" archive="$2" empreinte="$3" ; shift 3
    local commit="inconnu" branche="inconnue"
    commit=$(git rev-parse --short HEAD 2>/dev/null || echo "inconnu")
    branche=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "inconnue")

    {
        printf '{\n'
        printf '  "archive": "%s",\n'      "$(basename "$archive")"
        printf '  "horodatage_utc": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        printf '  "sha256": "%s",\n'       "$empreinte"
        printf '  "taille_octets": %s,\n'  "$(wc -c < "$archive" | tr -d ' ')"
        printf '  "commit": "%s",\n'       "$commit"
        printf '  "branche": "%s",\n'      "$branche"
        printf '  "machine": "%s",\n'      "$(hostname 2>/dev/null || echo inconnue)"
        printf '  "contenu": ['
        local premier=1 chemin
        for chemin in "$@"; do
            [[ $premier -eq 0 ]] && printf ','
            printf '\n    "%s"' "$chemin"
            premier=0
        done
        printf '\n  ]\n}\n'
    } > "$fichier"
}

sauvegarder() {
    local racine="$1"
    log_titre "Sauvegarde de MicroCRM"

    exiger_commandes tar

    # Détermination des sources : celles fournies, sinon l'ensemble par défaut.
    local -a candidates=()
    if [[ ${#SOURCES[@]} -gt 0 ]]; then
        candidates=("${SOURCES[@]}")
    else
        mapfile -t candidates < <(sources_par_defaut)
    fi

    # Filtrage : on ne conserve que ce qui existe réellement.
    local -a presentes=()
    local chemin
    for chemin in "${candidates[@]}"; do
        if [[ -e "$racine/$chemin" ]]; then
            presentes+=("$chemin")
            log_debug "inclus : $chemin"
        else
            log_avert "absent, ignoré : $chemin"
        fi
    done

    [[ ${#presentes[@]} -gt 0 ]] \
        || mourir "aucune source à sauvegarder : rien de ce qui était demandé n'existe." 1

    log_info "${#presentes[@]} source(s) retenue(s) : ${presentes[*]}"

    local stamp ; stamp=$(horodatage)
    local nom   ; nom=$(nom_archive "$PREFIXE" "$stamp")

    [[ "$DESTINATION" = /* ]] || DESTINATION="$racine/$DESTINATION"
    local archive="$DESTINATION/$nom"

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] archive qui serait créée : $archive"
        log_info "[SIMULATION] contenu : ${presentes[*]}"
        purger "$DESTINATION"
        return 0
    fi

    mkdir -p "$DESTINATION"
    log_info "création de l'archive : $archive"

    # -C "$racine" : les chemins stockés sont relatifs à la racine du dépôt,
    # ce qui rend l'archive restaurable n'importe où (pas de chemin absolu).
    tar -czf "$archive" -C "$racine" "${EXCLUSIONS[@]}" "${presentes[@]}" \
        || mourir "échec de la création de l'archive" 1

    local empreinte ; empreinte=$(empreinte_sha256 "$archive")
    printf '%s  %s\n' "$empreinte" "$nom" > "$archive.sha256"

    # Vérification immédiate : l'archive est relue intégralement.
    log_info "vérification de l'intégrité de l'archive…"
    tar -tzf "$archive" >/dev/null 2>&1 \
        || mourir "archive corrompue à la création — sauvegarde NON fiable" 5

    ecrire_manifeste "$archive.json" "$archive" "$empreinte" "${presentes[@]}"

    local taille ; taille=$(du -h "$archive" 2>/dev/null | awk '{print $1}' || echo '?')
    log_ok "sauvegarde vérifiée : $archive ($taille)"
    log_ok "empreinte SHA-256 : $empreinte"
    resume_ci "Sauvegarde" "$nom ($taille)"

    purger "$DESTINATION"
}

# Applique la décision de la fonction PURE `archives_a_purger`.
# La séparation décision/action est délibérée : la logique qui détermine
# QUOI supprimer est testée unitairement (tests/test_commun.sh), ce code-ci
# ne fait qu'exécuter une liste déjà validée.
purger() {
    local repertoire="$1"
    [[ -d "$repertoire" ]] || return 0

    local -a archives=()
    mapfile -t archives < <(find "$repertoire" -maxdepth 1 -name "${PREFIXE}_*.tar.gz" 2>/dev/null | sort)
    [[ ${#archives[@]} -eq 0 ]] && return 0

    local -a obsoletes=()
    mapfile -t obsoletes < <(archives_a_purger "$RETENTION" "${archives[@]}")

    if [[ ${#obsoletes[@]} -eq 0 ]]; then
        log_info "rétention : ${#archives[@]} archive(s) conservée(s) sur $RETENTION — aucune purge"
        return 0
    fi

    local fichier
    for fichier in "${obsoletes[@]}"; do
        if [[ $SIMULATION -eq 1 ]]; then
            log_info "[SIMULATION] serait supprimée : $(basename "$fichier")"
        else
            rm -f "$fichier" "$fichier.sha256" "$fichier.json"
            log_info "purgée : $(basename "$fichier")"
        fi
    done
    log_ok "${#obsoletes[@]} archive(s) purgée(s), $RETENTION conservée(s)"
}

restaurer() {
    log_titre "Restauration de MicroCRM"
    exiger_commandes tar

    [[ -n "$ARCHIVE" ]] || mourir "mode restauration : --archive est requis" 3
    [[ -f "$ARCHIVE" ]] || mourir "archive introuvable : $ARCHIVE" 1

    # L'intégrité est vérifiée AVANT toute écriture sur le disque.
    if [[ -f "$ARCHIVE.sha256" ]]; then
        log_info "vérification de l'empreinte SHA-256…"
        local attendue obtenue
        attendue=$(awk '{print $1}' < "$ARCHIVE.sha256")
        obtenue=$(empreinte_sha256 "$ARCHIVE")
        [[ "$attendue" == "$obtenue" ]] \
            || mourir "empreinte invalide — archive altérée, restauration REFUSÉE (attendu $attendue, obtenu $obtenue)" 5
        log_ok "empreinte conforme"
    else
        log_avert "aucun fichier .sha256 associé : intégrité non vérifiable"
    fi

    if [[ -d "$CIBLE" ]] && [[ -n "$(ls -A "$CIBLE" 2>/dev/null)" ]] && [[ $FORCER -eq 0 ]]; then
        mourir "le répertoire cible « $CIBLE » n'est pas vide — utilisez --forcer pour écraser" 1
    fi

    if [[ $SIMULATION -eq 1 ]]; then
        log_info "[SIMULATION] contenu qui serait restauré dans $CIBLE :"
        tar -tzf "$ARCHIVE" | head -30
        return 0
    fi

    mkdir -p "$CIBLE"
    tar -xzf "$ARCHIVE" -C "$CIBLE" || mourir "échec de l'extraction" 1

    local nb ; nb=$(tar -tzf "$ARCHIVE" | wc -l | tr -d ' ')
    log_ok "restauration terminée : $nb entrée(s) extraite(s) dans $CIBLE"
    resume_ci "Restauration" "$nb entrées depuis $(basename "$ARCHIVE")"
}

principal() {
    analyser_arguments "$@"
    local debut ; debut=$(date +%s)
    local racine ; racine=$(racine_projet)

    case "$MODE" in
        sauvegarde)   sauvegarder "$racine" ;;
        restauration) restaurer ;;
    esac

    local duree=$(( $(date +%s) - debut ))
    log_titre "Terminé en $(duree_lisible "$duree")"
}

principal "$@"
