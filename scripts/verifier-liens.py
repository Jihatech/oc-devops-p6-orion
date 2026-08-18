#!/usr/bin/env python3
# =============================================================================
# verifier-liens.py — Vérification des liens relatifs de la documentation
# =============================================================================
#
# BUT
#   Détecter les liens Markdown qui pointent vers un fichier absent du DÉPÔT.
#   Un lien mort dans un dépôt public donne à l'évaluateur — ou à un
#   collègue — l'impression d'une preuve annoncée mais introuvable, ce qui est
#   pire que de ne rien annoncer du tout.
#
#   Ce script existe à cause d'un défaut réel : la règle `*.log` du .gitignore
#   avait silencieusement exclu les trois traces d'exécution de la
#   démonstration de rollback, alors que le README les référençait. Les
#   fichiers étaient présents sur le poste, donc tout paraissait normal en
#   local ; ils étaient absents du dépôt public, donc les liens étaient morts.
#
# FONCTIONNEMENT
#   1. Recense les fichiers RÉELLEMENT SUIVIS par Git (`git ls-files`), et non
#      ceux présents sur le disque. C'est le cœur du contrôle : un fichier
#      ignoré existe en local mais pas pour un tiers qui clone le dépôt.
#   2. Extrait de chaque fichier Markdown les liens relatifs, en écartant les
#      URL absolues (http, https, mailto) et les ancres pures (#section).
#   3. Résout chaque cible par rapport au répertoire du document, retire une
#      éventuelle ancre, et vérifie qu'elle correspond à un fichier suivi ou à
#      un répertoire contenant au moins un fichier suivi.
#   4. Rapporte tous les liens cassés, groupés par fichier source.
#
# PARAMÈTRES
#   -r, --racine <répertoire>   Racine du dépôt        (défaut : détectée par git)
#   -c, --cible <répertoire>    Périmètre à vérifier ; répétable
#                               (défaut : docs et la racine)
#   -v, --verbeux               Détaille chaque lien vérifié
#
# CONDITIONS D'EXÉCUTION
#   - Python >= 3.8, aucune dépendance externe.
#   - Exécution dans un dépôt Git (le script s'appuie sur `git ls-files`).
#   - Aucun accès réseau : les liens externes ne sont volontairement PAS
#     testés. Vérifier des URL distantes rendrait le pipeline dépendant de
#     sites tiers et produirait des échecs sans rapport avec le dépôt.
#   - Codes de sortie : 0 aucun lien cassé · 1 au moins un lien cassé
#     · 2 prérequis manquant
#
# EXEMPLES
#   python3 scripts/verifier-liens.py
#   python3 scripts/verifier-liens.py --cible docs --verbeux
#
# AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
# =============================================================================

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import PurePosixPath

# Capture [libellé](cible) sans consommer les images ![...](...) : celles-ci
# sont également vérifiées, une image manquante étant tout aussi visible.
MOTIF_LIEN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")

PREFIXES_EXTERNES = ("http://", "https://", "mailto:", "tel:", "ftp://", "//")


def fichiers_suivis(racine: str) -> set[str]:
    """Retourne l'ensemble des chemins suivis par Git, en style POSIX."""
    try:
        sortie = subprocess.run(
            ["git", "ls-files"],
            cwd=racine,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as err:
        print(f"[ERREUR] impossible d'interroger Git : {err}", file=sys.stderr)
        sys.exit(2)
    return {ligne.strip() for ligne in sortie.splitlines() if ligne.strip()}


def racine_depot() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "."


def est_externe(cible: str) -> bool:
    return cible.startswith(PREFIXES_EXTERNES) or cible.startswith("#")


def normaliser(source: str, cible: str) -> str | None:
    """Résout une cible relative par rapport au document qui la référence.

    Retourne None si le lien n'a pas à être vérifié (externe, ancre pure).
    """
    cible = cible.strip().split(" ")[0]  # retire un éventuel titre entre guillemets
    if not cible or est_externe(cible):
        return None
    cible = cible.split("#", 1)[0]  # retire l'ancre
    if not cible:
        return None
    base = PurePosixPath(source).parent
    resolu = (base / cible) if not cible.startswith("/") else PurePosixPath(cible.lstrip("/"))
    # Normalisation manuelle des « .. » : PurePosixPath ne les réduit pas.
    parties: list[str] = []
    for partie in PurePosixPath(resolu).parts:
        if partie == "..":
            if parties:
                parties.pop()
        elif partie not in (".", ""):
            parties.append(partie)
    return "/".join(parties)


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(
        prog="verifier-liens.py",
        description="Vérifie que les liens relatifs de la documentation pointent vers des fichiers versionnés.",
    )
    analyseur.add_argument("-r", "--racine", default=None)
    analyseur.add_argument("-c", "--cible", action="append")
    analyseur.add_argument("-v", "--verbeux", action="store_true")
    args = analyseur.parse_args(argv if argv is not None else sys.argv[1:])

    racine = args.racine or racine_depot()
    suivis = fichiers_suivis(racine)
    if not suivis:
        print("[ERREUR] aucun fichier suivi par Git n'a été trouvé.", file=sys.stderr)
        return 2

    # Répertoires contenant au moins un fichier suivi : un lien vers un
    # dossier (par exemple `docs/captures/rollback/`) est légitime.
    repertoires = {str(PurePosixPath(f).parent) for f in suivis}
    for chemin in list(repertoires):
        parties = PurePosixPath(chemin).parts
        for i in range(1, len(parties)):
            repertoires.add("/".join(parties[:i]))

    perimetres = args.cible or ["docs", ""]
    documents = sorted(
        f for f in suivis
        if f.endswith(".md") and any(f.startswith(p) for p in perimetres)
    )

    casses: list[tuple[str, str, str]] = []
    verifies = 0

    for document in documents:
        try:
            with open(f"{racine}/{document}", encoding="utf-8", errors="replace") as flux:
                contenu = flux.read()
        except OSError as err:
            print(f"[AVERT] {document} illisible : {err}", file=sys.stderr)
            continue

        for brut in MOTIF_LIEN.findall(contenu):
            cible = normaliser(document, brut)
            if cible is None:
                continue
            verifies += 1
            if cible in suivis or cible in repertoires:
                if args.verbeux:
                    print(f"  ok   {document} -> {cible}")
            else:
                casses.append((document, brut, cible))

    print(f"{len(documents)} document(s) analysé(s), {verifies} lien(s) relatif(s) vérifié(s).")

    if casses:
        print(f"\n{len(casses)} lien(s) cassé(s) :\n", file=sys.stderr)
        courant = None
        for document, brut, cible in casses:
            if document != courant:
                print(f"  {document}", file=sys.stderr)
                courant = document
            print(f"    [{brut}] -> « {cible} » absent du dépôt", file=sys.stderr)
        print(
            "\nRappel : le contrôle porte sur les fichiers SUIVIS par Git. "
            "Un fichier présent en local mais ignoré (.gitignore) est absent pour "
            "quiconque clone le dépôt.",
            file=sys.stderr,
        )
        return 1

    print("Aucun lien cassé.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
