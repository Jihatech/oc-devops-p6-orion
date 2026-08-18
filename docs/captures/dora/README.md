# Preuves — indicateurs DORA

> Mesures calculées par [`scripts/dora-metrics.py`](../../../scripts/dora-metrics.py) sur
> **l'historique réel** du dépôt, via l'API GitHub. Aucune donnée n'est saisie à la main.
>
> Productions : [`RESUME.md`](RESUME.md) (rapport lisible), [`dora-metrics.json`](dora-metrics.json)
> (données brutes), [`historique-dora.csv`](historique-dora.csv) (tendance),
> [`dora-elk.ndjson`](dora-elk.ndjson) (ingestion Elasticsearch).

## Ce qui a été mesuré

| Indicateur | Valeur | Niveau DORA |
|---|---|---|
| Fréquence de déploiement | 12,71 / semaine | ⚪ **non représentatif** |
| Délai de livraison (médiane) | **36,7 h** | 🟢 High |
| Taux d'échec des changements | **44,4 %** | 🔴 Low |
| Délai de rétablissement (médiane) | **7 min** | 🟢 Elite |

Volumétrie : **18 exécutions de pipeline, 3 releases, 45 commits**.

## Lire ces chiffres honnêtement

Un tableau de bord qui ne présente que des voyants verts n'apprend rien à personne. Ces quatre
mesures doivent être lues avec leur contexte — et deux d'entre elles appellent une mise en garde
explicite.

### 🔴 Taux d'échec 44,4 % — réel, et attendu

**8 exécutions en échec sur 18.** C'est très au-dessus du seuil « Elite » (5 %), et le chiffre est
exact. Il faut cependant dire ce qu'il mesure ici :

> Ces 18 exécutions couvrent la **construction du pipeline lui-même**, pas l'exploitation d'une
> chaîne stabilisée. Les échecs sont ceux du travail d'ingénierie : bit exécutable manquant sur
> `gradlew`, option `bash_unit` incorrecte, `grep` sans correspondance sous `pipefail`, verrou npm
> incompatible avec `npm ci`, syntaxe `npx` erronée.

Chacun a été corrigé **et transformé en garde-fou** (voir `docs/JOURNAL_IA.md`). Aucun ne
correspond à un changement applicatif ayant échoué en production — situation que cet indicateur
vise normalement.

**Ce chiffre est donc une ligne de base, pas un verdict.** Il devient significatif à partir du
moment où la chaîne est stable, ce qui est précisément l'état atteint en fin de projet. C'est
d'ailleurs ce qui le rend intéressant à conserver : la comparaison future se fera contre lui.

### ⚪ Fréquence de déploiement — volontairement non notée

Le calcul donne 12,71 déploiements par semaine, ce qui placerait le projet au niveau « Elite ».
**Le script refuse pourtant de lui attribuer un niveau**, et c'est délibéré : la période observée
ne couvre que **1,65 jour**. Trois releases divisées par 1,65 jour produisent un nombre exact et
dépourvu de sens.

Ce garde-fou a été ajouté **après un premier calcul aberrant** : en prenant pour origine la
première release — publiée deux heures plus tôt —, le script annonçait **236 déploiements par
semaine**. Le chiffre était mathématiquement juste et complètement faux.

La période court désormais depuis la **première activité observée** (commit ou release, au plus
tôt), et tout résultat portant sur moins de 14 jours est marqué non représentatif. La valeur reste
publiée — masquer une mesure serait pire que la nuancer.

### 🟢 Délai de rétablissement 7 minutes — flatteur, et à relativiser

Excellent chiffre, mais il mesure ici la réactivité d'**une seule personne travaillant en continu
sur le pipeline**, pas la capacité d'une équipe d'astreinte à rétablir un service en production.
Il se dégradera mécaniquement en conditions réelles, et c'est normal.

### 🟢 Délai de livraison 36,7 heures — le plus représentatif des quatre

C'est la mesure la plus solide du lot : elle porte sur 45 commits effectivement livrés par 3
releases. La médiane est retenue plutôt que la moyenne, un commit ancien repris tardivement
décalant la moyenne sans rien dire du flux réel.

## Conventions de calcul — et pourquoi elles comptent

Les indicateurs DORA n'ont de sens que si l'on précise ce qu'on appelle un « déploiement ». Les
conventions retenues sont documentées en tête du script, et discutables — c'est justement pourquoi
elles sont écrites.

| Indicateur | Convention retenue | Alternative écartée |
|---|---|---|
| **Déploiement** | Une **release publiée** par semantic-release | Compter les exécutions de pipeline gonflerait la fréquence : toutes ne livrent rien |
| **Lead time** | **Médiane** commit → release qui l'embarque | La moyenne, sensible à un unique commit ancien |
| **Change failure rate** | Exécutions en échec sur `main` / total sur `main` | Restreindre aux seules releases donnerait 0 % — vrai mais inutile |
| **MTTR** | Médiane échec → **premier succès suivant** | Compter chaque échec consécutif séparément gonflerait le nombre d'incidents ; la chaîne reste indisponible tant qu'aucun succès n'est survenu |

## Pourquoi un script sur mesure

Aucune solution gratuite ne couvre correctement les quatre indicateurs sur GitHub. Trois raisons
ont conduit à l'écrire :

1. **Transparence** — les définitions sont lisibles, donc contestables. Une boîte noire SaaS
   produirait un chiffre indéfendable en soutenance.
2. **Aucune dépendance** — bibliothèque standard Python seule, jeton en lecture seule, aucun
   service tiers.
3. **Adaptabilité** — la convention « déploiement = release » sera remplacée par « déploiement =
   `helm upgrade` réussi » le jour où l'application ira en production, sans changer le reste.

## Reproduire la mesure

```bash
export GITHUB_TOKEN=$(gh auth token)     # sans jeton : 60 requêtes/heure
python3 scripts/dora-metrics.py --depot Jihatech/oc-devops-p6-orion --jours 90
```

Chaque exécution **ajoute une ligne** à `historique-dora.csv`. C'est ce fichier qui porte la
tendance — la seule lecture réellement utile de ces indicateurs sur la durée.

Le fichier `dora-elk.ndjson` est directement ingérable par Elasticsearch (`_bulk`) ou Filebeat :
un document par indicateur, horodaté, prêt à alimenter un tableau de bord Kibana.
