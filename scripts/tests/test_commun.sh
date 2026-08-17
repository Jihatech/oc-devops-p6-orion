#!/usr/bin/env bash
# =============================================================================
# test_commun.sh — Tests unitaires bash_unit de la bibliothèque commune
# =============================================================================
#
# BUT
#   Couvrir par des tests unitaires les fonctions critiques de
#   `scripts/lib/commun.sh` — celles dont un défaut aurait des conséquences
#   réelles : validation des paramètres, nommage des archives et surtout
#   `archives_a_purger`, qui décide de la SUPPRESSION de sauvegardes.
#
#   L'accent est mis sur les cas limites (rétention nulle, négative, non
#   numérique, liste vide, égalité stricte) : ce sont eux qui provoquent les
#   pertes de données en production, pas le cas nominal.
#
# FONCTIONNEMENT
#   Exécuté par bash_unit. Chaque fonction `test_*` est un cas de test
#   indépendant. `setup_suite` source la bibliothèque une seule fois — ce qui
#   n'est possible que parce que `commun.sh` n'a aucun effet de bord au
#   chargement.
#
# PARAMÈTRES
#   Aucun. S'exécute via :  bash_unit scripts/tests/test_commun.sh
#
# CONDITIONS D'EXÉCUTION
#   - bash_unit installé (https://github.com/pgrange/bash_unit)
#   - Bash >= 4 (mapfile)
#   - Aucun accès réseau, aucun privilège, aucun effet de bord sur le système :
#     toutes les fonctions testées ici sont pures.
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

setup_suite() {
    RACINE_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=scripts/lib/commun.sh
    source "$RACINE_SCRIPTS/lib/commun.sh"
    # Couleur désactivée : les comparaisons de chaînes doivent porter sur le
    # texte, pas sur des séquences d'échappement ANSI.
    export ORION_COULEUR=0
}

# -----------------------------------------------------------------------------
# valider_composant
# -----------------------------------------------------------------------------

test_valider_composant_accepte_les_valeurs_autorisees() {
    assert "valider_composant front" "« front » doit être accepté"
    assert "valider_composant back"  "« back » doit être accepté"
    assert "valider_composant tous"  "« tous » doit être accepté"
}

test_valider_composant_refuse_les_valeurs_inconnues() {
    assert_fails "valider_composant frontend" "« frontend » n'est pas un composant valide"
    assert_fails "valider_composant FRONT"    "la validation doit être sensible à la casse"
    assert_fails "valider_composant ''"       "une valeur vide doit être refusée"
    assert_fails "valider_composant"          "l'absence d'argument doit être refusée"
}

# -----------------------------------------------------------------------------
# composants_de
# -----------------------------------------------------------------------------

test_composants_de_developpe_tous() {
    assert_equals "front
back" "$(composants_de tous)" "« tous » doit se développer en front puis back"
}

test_composants_de_retourne_un_seul_composant() {
    assert_equals "front" "$(composants_de front)"
    assert_equals "back"  "$(composants_de back)"
}

test_composants_de_echoue_sur_valeur_invalide() {
    assert_fails "composants_de inexistant" "une valeur inconnue doit faire échouer la fonction"
}

# -----------------------------------------------------------------------------
# valider_environnement
# -----------------------------------------------------------------------------

test_valider_environnement_accepte_les_trois_environnements() {
    assert "valider_environnement dev"
    assert "valider_environnement staging"
    assert "valider_environnement prod"
}

test_valider_environnement_refuse_le_reste() {
    assert_fails "valider_environnement production" "« production » n'est pas la valeur canonique attendue"
    assert_fails "valider_environnement ''"
}

# -----------------------------------------------------------------------------
# horodatage / nom_archive
# -----------------------------------------------------------------------------

test_horodatage_respecte_le_format_attendu() {
    local stamp ; stamp=$(horodatage)
    assert_matches "^[0-9]{8}-[0-9]{6}$" "$stamp" \
        "l'horodatage doit être au format AAAAMMJJ-HHMMSS (obtenu : $stamp)"
}

test_horodatage_a_une_longueur_fixe() {
    # Longueur fixe = tri alphabétique équivalent au tri chronologique.
    # C'est l'hypothèse sur laquelle repose archives_a_purger.
    local stamp ; stamp=$(horodatage)
    assert_equals "15" "${#stamp}" "l'horodatage doit toujours faire 15 caractères"
}

test_nom_archive_construit_le_nom_canonique() {
    assert_equals "microcrm_20260817-020000.tar.gz" \
        "$(nom_archive microcrm 20260817-020000)"
}

test_nom_archive_respecte_le_prefixe_fourni() {
    assert_equals "orion-prod_20260101-000000.tar.gz" \
        "$(nom_archive orion-prod 20260101-000000)"
}

# -----------------------------------------------------------------------------
# archives_a_purger — FONCTION CRITIQUE (décide de suppressions)
# -----------------------------------------------------------------------------

test_purge_ne_supprime_rien_si_moins_d_archives_que_la_retention() {
    assert_equals "" "$(archives_a_purger 7 a_1.tar.gz a_2.tar.gz a_3.tar.gz)" \
        "3 archives pour une rétention de 7 : aucune suppression"
}

test_purge_ne_supprime_rien_a_egalite_stricte() {
    # Cas limite classique : total == rétention ne doit RIEN supprimer.
    assert_equals "" "$(archives_a_purger 3 a_1.tar.gz a_2.tar.gz a_3.tar.gz)" \
        "3 archives pour une rétention de 3 : aucune suppression"
}

test_purge_supprime_les_plus_anciennes_seulement() {
    local resultat
    resultat=$(archives_a_purger 2 \
        microcrm_20260101-000000.tar.gz \
        microcrm_20260102-000000.tar.gz \
        microcrm_20260103-000000.tar.gz \
        microcrm_20260104-000000.tar.gz)

    assert_equals "microcrm_20260101-000000.tar.gz
microcrm_20260102-000000.tar.gz" "$resultat" \
        "seules les 2 plus anciennes doivent être purgées"
}

test_purge_est_independante_de_l_ordre_des_arguments() {
    # La fonction trie elle-même : l'ordre de `find` ne doit pas influer
    # sur la décision. Un défaut ici supprimerait les archives récentes.
    local resultat
    resultat=$(archives_a_purger 1 \
        microcrm_20260103-000000.tar.gz \
        microcrm_20260101-000000.tar.gz \
        microcrm_20260102-000000.tar.gz)

    assert_equals "microcrm_20260101-000000.tar.gz
microcrm_20260102-000000.tar.gz" "$resultat" \
        "le tri interne doit rendre le résultat indépendant de l'ordre reçu"
}

test_purge_conserve_tout_si_retention_nulle() {
    # GARDE-FOU MAJEUR : une variable vide ou à 0 ne doit jamais être
    # interprétée comme « tout supprimer ».
    assert_equals "" "$(archives_a_purger 0 a_1.tar.gz a_2.tar.gz a_3.tar.gz)" \
        "une rétention de 0 ne doit RIEN supprimer"
}

test_purge_conserve_tout_si_retention_non_numerique() {
    assert_equals "" "$(archives_a_purger abc a_1.tar.gz a_2.tar.gz)" \
        "une rétention non numérique ne doit RIEN supprimer"
    assert_equals "" "$(archives_a_purger '' a_1.tar.gz a_2.tar.gz)" \
        "une rétention vide ne doit RIEN supprimer"
    assert_equals "" "$(archives_a_purger -5 a_1.tar.gz a_2.tar.gz)" \
        "une rétention négative ne doit RIEN supprimer"
}

test_purge_gere_une_liste_vide() {
    assert_equals "" "$(archives_a_purger 3)" \
        "aucune archive fournie : aucune suppression, aucune erreur"
}

test_purge_supprime_tout_sauf_une_avec_retention_1() {
    local resultat
    resultat=$(archives_a_purger 1 b_1.tar.gz b_2.tar.gz b_3.tar.gz)
    assert_equals "b_1.tar.gz
b_2.tar.gz" "$resultat" "seule la plus récente doit survivre"
}

# -----------------------------------------------------------------------------
# attribut_xml — régression : « operand expected » sur attribut absent
# -----------------------------------------------------------------------------

test_attribut_xml_lit_un_attribut_present() {
    local ligne='<testsuite name="Suite" tests="8" failures="0" errors="0" skipped="2">'
    assert_equals "8" "$(attribut_xml "$ligne" tests)"
    assert_equals "0" "$(attribut_xml "$ligne" failures)"
    assert_equals "2" "$(attribut_xml "$ligne" skipped)"
}

test_attribut_xml_retourne_zero_si_attribut_absent() {
    # Cas réel : karma-junit-reporter n'émet pas « skipped », contrairement à
    # Gradle. La chaîne vide qui en résultait cassait l'arithmétique et faisait
    # échouer un job dont tous les tests étaient pourtant passés.
    local ligne='<testsuite name="Chrome Headless" tests="8" errors="0" failures="0" time="0.12">'
    assert_equals "0" "$(attribut_xml "$ligne" skipped)" \
        "un attribut absent doit valoir 0, jamais une chaîne vide"
    # Vérifie que la valeur est bien utilisable en arithmétique.
    local somme=$(( 0 + $(attribut_xml "$ligne" skipped) ))
    assert_equals "0" "$somme" "le résultat doit être injectable dans une expression arithmétique"
}

test_attribut_xml_gere_une_ligne_vide() {
    assert_equals "0" "$(attribut_xml "" tests)"
    assert_equals "0" "$(attribut_xml "<testsuite/>" tests)"
}

test_attribut_xml_ne_confond_pas_les_attributs_de_prefixe_proche() {
    # « tests » ne doit pas capter la valeur de « testsuite-id ».
    local ligne='<testsuite tests="5" failures="1">'
    assert_equals "5" "$(attribut_xml "$ligne" tests)"
    assert_equals "1" "$(attribut_xml "$ligne" failures)"
}

# -----------------------------------------------------------------------------
# verifier_commande
# -----------------------------------------------------------------------------

test_verifier_commande_detecte_une_commande_existante() {
    assert "verifier_commande bash" "bash doit être détecté"
}

test_verifier_commande_signale_une_commande_absente() {
    assert_fails "verifier_commande commande_qui_n_existe_pas_orion_p6" \
        "une commande absente doit retourner un code non nul"
}

# -----------------------------------------------------------------------------
# duree_lisible
# -----------------------------------------------------------------------------

test_duree_lisible_sous_une_minute() {
    assert_equals "0s"  "$(duree_lisible 0)"
    assert_equals "45s" "$(duree_lisible 45)"
    assert_equals "59s" "$(duree_lisible 59)"
}

test_duree_lisible_au_dela_d_une_minute() {
    assert_equals "1m 00s" "$(duree_lisible 60)"
    assert_equals "1m 23s" "$(duree_lisible 83)"
    assert_equals "10m 05s" "$(duree_lisible 605)"
}
