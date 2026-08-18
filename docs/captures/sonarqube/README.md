# Preuves d'analyse SonarQube

> Preuves conservées des analyses SonarQube de MicroCRM, et **comparaison avant/après**
> des corrections apportées (critère de la fiche d'autoévaluation :
> « vulnérabilités identifiées → priorisées → corrigées »).

## Pourquoi ce répertoire existe

Le serveur SonarQube du pipeline est **éphémère** : il est démarré en conteneur au début du job et
détruit à la fin. Son tableau de bord n'est donc pas consultable après coup, et aucune capture
d'écran ne peut en être tirée a posteriori.

`scripts/sonar-report.py` interroge l'API du serveur **avant sa destruction** et écrit ici trois
productions durables :

| Fichier | Contenu |
|---|---|
| `historique.csv` | Une ligne par analyse — **c'est la trace de tendance** |
| `RESUME.md` | Rapport lisible de la dernière analyse (gate, mesures, issues, hotspots) |
| `analyse-<horodatage>.json` | Données brutes complètes, rejouables |

Cette trace est **plus solide qu'une capture d'écran** : elle est datée, rattachée à un commit et à
une exécution de pipeline, comparable automatiquement, et elle ne peut pas être retouchée sans que
l'historique Git ne le montre.

## Comment l'historique s'enrichit

L'historique versionné est présent dans le dépôt au moment du `checkout` ; le script y **ajoute** la
ligne de l'analyse en cours. L'artefact `preuves-sonarqube` de chaque exécution contient donc
l'historique complet, et non la seule dernière mesure.

Le versement dans le dépôt reste un **acte manuel et délibéré**, effectué aux jalons du projet :

```bash
gh run download <id> -n preuves-sonarqube -D /tmp/preuves
cp /tmp/preuves/* docs/captures/sonarqube/
git add docs/captures/sonarqube && git commit -m "docs(preuves): analyse SonarQube du <date>"
```

Ce choix est assumé : donner au pipeline le droit d'écrire dans le dépôt (`contents: write`)
élargirait ses permissions bien au-delà de ce que justifie la publication d'une mesure.

## Comparaison avant / après

| Indicateur | Avant (`bc6d7a9`) | Après (`6b391eb`) | Écart |
|---|---|---|---|
| Quality gate | ✅ OK | ✅ OK | — |
| **Bugs** | **2** | **0** | **−2** ✅ |
| Vulnérabilités | 0 | 0 | — |
| Security hotspots | 0 | 0 | — |
| Code smells | 35 | **33** | −2 |
| **Note de fiabilité** | **C** | **A** | **+2 niveaux** ✅ |
| Note de sécurité | A | A | — |
| Note de maintenabilité | A | A | — |
| Couverture | 37,4 % | 37,4 % | — |
| Duplication | 2,5 % | 2,4 % | −0,1 pt |
| Lignes de code | 960 | 967 | +7 |

### Les 4 défauts corrigés, par ordre de priorité

| Règle | Sévérité | Emplacement | Correction |
|---|---|---|---|
| `java:S1186` | **CRITICAL** | `MicroCRMApplicationTests.contextLoads()` | Méthode de test **vide** : elle passait toujours sans rien vérifier, donnant une fausse assurance. Assertions explicites ajoutées sur le contexte Spring. |
| `typescript:S7059` | **CRITICAL** | `person-details.component.ts:33` | Appel **asynchrone dans le constructeur** : rend le composant difficile à tester et peut résoudre la promesse avant l'initialisation. Déplacé dans `ngOnInit`. |
| `Web:S5256` | MAJOR | `person-details.component.html:179` | **Tableau sans en-têtes** : un lecteur d'écran ne peut associer une cellule à sa colonne. `<thead>` et `<th scope="col">` ajoutés. |
| `Web:MouseEventWithoutKeyboardEquivalentCheck` | MINOR | `person-details.component.html:171` | **Clic porté par un `<span>`**, non focalisable : fonction inaccessible sans souris. Gestionnaire déplacé sur le `<button>` englobant, nativement accessible — plutôt que d'ajouter un gestionnaire clavier à un élément qui n'aurait pas dû en porter. |

**Effet collatéral mesuré** : les avertissements ESLint passent de **12 à 10**, les deux corrections
d'accessibilité étant également détectées par ESLint. Deux outils, un même défaut réel : c'est un
signe de cohérence de la chaîne, pas une redondance.

## Lecture des résultats — points à souligner

**0 vulnérabilité et 0 security hotspot.** Ce n'est pas une lacune de la configuration : l'analyseur
Java a bien fonctionné (les classes compilées lui étaient fournies, sans quoi il n'aurait rien pu
détecter). L'application est simple — un CRUD sans authentification, sans cryptographie, sans appels
sortants — et la faille réelle qu'elle porte (**API REST sans authentification**, risque R1) relève
d'une **absence de contrôle**, que l'analyse statique ne peut pas détecter : SonarQube signale du
code dangereux, pas du code manquant. Ce risque est documenté dans `docs/05-plan-securite.md` §8.

**La quality gate était déjà passée « avant ».** La gate « Sonar way » porte par défaut sur le
**code nouveau**, pas sur l'existant : les 2 bugs préexistants ne la faisaient pas échouer. Les
corriger relevait donc d'une décision volontaire, pas d'une contrainte du pipeline — et c'est
précisément ce que demande le critère « identifiées → priorisées → corrigées ».

**La couverture reste à 37,4 %.** Elle n'a pas été l'objet de ces corrections. Le plan de tests
(`docs/04-plan-tests.md` §8) en fait la priorité n°1 d'amélioration, avec un point notable : la
mesure contredit la perception de l'équipe — 30,8 % côté frontend, où elle se déclare « Bonne »,
contre 65,9 % côté backend, où elle se déclare « Débutante ».

## Consultation locale du tableau de bord

Pour explorer l'interface SonarQube et en tirer des captures d'écran :

```bash
./scripts/sonar-analyse.sh --demarrer        # démarre le serveur, analyse, NE l'arrête pas
# → http://localhost:9000
# Le script affiche « identifiants  admin / <mot de passe> » en fin d'initialisation.
# Ce mot de passe est généré aléatoirement à chaque exécution et n'est affiché QUE
# hors CI : dans un journal GitHub Actions, il est masqué (::add-mask::).
docker rm -f orion-sonarqube                 # arrêt manuel une fois les captures prises
```
