# 04 — Plan de tests

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Application** : MicroCRM — Angular 17 (frontend) + Spring Boot 3.2.5 / Java 17 (backend)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Documents liés** : `01-audit-swot.md` (constats), `03-normalisation-plan-ci.md` (pipeline),
> `05-plan-securite.md` (volet sécurité)

---

## 1. Objectifs du plan de tests

| # | Objectif | Constat d'origine | Indicateur de succès |
|---|---|---|---|
| **O1** | **Mesurer** la couverture, aujourd'hui inconnue | C6, C7 : `karma-coverage` installé mais inexploitable, aucun JaCoCo | Couverture publiée à chaque exécution |
| **O2** | **Empêcher la dette de croître** sur le code nouveau | f7 : qualité non mesurée, équipe Débutante en JUnit | ≥ 60 % de couverture sur le code nouveau |
| **O3** | **Détecter au plus tôt**, au coût le plus faible | P1 *fail fast* | Retour de lint < 1 min, pipeline complet < 12 min |
| **O4** | **Rendre les tests reproductibles** poste ↔ CI | C4 : images non épinglées, chemin Chrome codé en dur | Même script, même verdict des deux côtés |
| **O5** | **Fiabiliser les scripts d'exploitation** eux-mêmes | f3, f8 : automatisation à construire | 100 % des fonctions critiques couvertes |
| **O6** | **Vérifier la réversibilité**, pas seulement l'aller | f8 : ni back-up ni rollback | Cycle sauvegarde → restauration testé à chaque exécution |

> **Principe directeur** : le périmètre du test ne s'arrête pas au code applicatif. Chez Orion, le
> risque principal n'est pas un bug fonctionnel — l'application est simple et n'est pas en production —
> mais **la chaîne de livraison elle-même**, entièrement manuelle. Les scripts d'automatisation et la
> procédure de sauvegarde sont donc testés au même titre que le code.

---

## 2. Typologie des tests

### 2.1 Vue d'ensemble

| # | Type de test | Périmètre | Outil | Emplacement | Fréquence | Bloquant |
|---|---|---|---|---|---|---|
| **T1** | Analyse statique — frontend | TypeScript, templates HTML | ESLint 8.57 + `@angular-eslint` 17.5 | Étape ① lint | Chaque *push* et PR | ✅ sur erreur |
| **T2** | Analyse statique — scripts | Bash | ShellCheck 0.11.0 (`--severity=style`) | Étape ① lint | Chaque *push* et PR | ✅ |
| **T3** | Analyse statique — Python | `notify.py`, `sonar-report.py` | `py_compile` | Étape ① lint | Chaque *push* et PR | ✅ |
| **T4** | Contrôle d'intégrité du dépôt | Bits exécutables (`scripts/*.sh`, `gradlew`) | Script maison | Étape ① lint | Chaque *push* et PR | ✅ |
| **T5** | Tests unitaires — frontend | Composants, services Angular | Karma 6.4 + Jasmine 5.1 | Étape ③ test | Chaque *push* et PR | ✅ |
| **T6** | Tests unitaires — backend | Classes Java | JUnit 5 (JUnit Platform) | Étape ③ test | Chaque *push* et PR | ✅ |
| **T7** | Test d'intégration — backend | Contexte Spring + repository JPA | Spring Boot Test | Étape ③ test | Chaque *push* et PR | ✅ |
| **T8** | Tests unitaires — scripts | Fonctions pures de `lib/commun.sh` | bash_unit 2.3.3 | Étape ③ test | Chaque *push* et PR | ✅ |
| **T9** | **Test de restauration** | Cycle sauvegarde → restauration → `diff -r` | `backup.sh` + `diff` | Étape ③ test | Chaque *push* et PR | ✅ |
| **T10** | Analyse de qualité et de sécurité du code | Monorepo entier | SonarQube Community 25.12 | Étape ④ security | Chaque *push* et PR | ✅ quality gate |
| **T11** | Analyse des dépendances | npm + bibliothèques Java du JAR | `npm audit` + Trivy `fs` | Étape ④ security | Chaque *push* et PR | ✅ si CRITICAL corrigible |
| **T12** | Détection de secrets | Dépôt entier | Trivy `secret` | Étape ④ security | Chaque *push* et PR | ✅ **inconditionnel** |
| **T13** | Analyse des configurations | Dockerfile, manifestes | Trivy `config` | Étape ④ security | Chaque *push* et PR | ⚠️ avertissement (phase 3) |
| **T14** | Test de fumée post-déploiement | Service HTTP en fonctionnement | `deploy-build.sh` (sonde) | Déploiement | Chaque déploiement | ✅ + rollback auto |
| **T15** | Test de rollback | Retour à la version N-1 | `helm rollback` | Déploiement | À chaque release *(phase 4)* | ✅ |
| **T16** | Re-scan des images publiées | Images déjà dans le registre | Trivy `image` | Planifié | **Hebdomadaire** *(phase 4)* | ⚠️ alerte |
| **T17** | **Test de charge** | Chaîne complète via le Service Kubernetes | k6 0.55 en conteneur | Manuel | À chaque évolution d'architecture | ✅ seuils p95 et erreurs |

### 2.2 Ce qui est délibérément **hors périmètre**

Le guide mentor est explicite : *« il n'est pas nécessaire d'implémenter toutes les recommandations »*
et *« finaliser dans les délais plutôt que viser la perfection »*. Ces types de tests ont été étudiés
puis écartés, avec leur motif :

| Type de test | ❌ Motif d'exclusion | Condition de réintroduction |
|---|---|---|
| **Tests E2E** (Cypress/Playwright) | Périmètre fonctionnel minimal (CRUD personnes/organisations) ; coût de mise en place et de maintenance sans commune mesure avec le gain. T5 à T7 plus le test de fumée T14 couvrent l'essentiel du risque. | Dès que des parcours multi-écrans à enjeu apparaissent |
| **DAST** (OWASP ZAP) | Exige un environnement déployé et stable dans la CI ; prématuré tant que la chaîne de déploiement n'est pas fiabilisée. | Une fois le déploiement Kubernetes stabilisé (phase 4) |
| **Tests de mutation** (PIT) | Pertinents seulement une fois une couverture significative atteinte ; ici la couverture est le problème, pas sa qualité. | Au-delà de 70 % de couverture backend |
| **Tests de contrat** (Pact) | Un seul consommateur, un seul producteur, développés par la même équipe. | En cas d'ouverture de l'API à des tiers |

### 2.3 Le test de charge (T17) — paliers et seuils

Ajouté après la campagne exécutée le 19/08/2026. Preuves complètes :
[`docs/captures/charge/RESUME.md`](captures/charge/RESUME.md).

| Palier | Utilisateurs virtuels | Durée de mesure | Objet |
|---|---|---|---|
| **nominal** | 5 | 2 min | Usage courant de l'équipe d'Orion |
| **soutenu** | 25 | 3 min | Pointe d'activité plausible |
| **pointe** | 50 | 3 min | Au-delà de l'usage attendu |
| **saturation** | 300 | 4 min | **Hors caractérisation** : vérifier que l'alerte se déclenche |

| Seuil | Valeur | Justification |
|---|---|---|
| 95e centile | **< 500 ms** | Au-delà d'une demi-seconde, l'utilisateur perçoit l'attente. Le 95e centile plutôt que la moyenne : c'est la lenteur subie par les 5 % les moins bien servis qui compte. |
| Taux d'erreur | **< 1 %** | Une erreur sur cent est déjà visible sur un CRM utilisé quotidiennement. |

**Un échauffement précède chaque mesure et en est exclu.** Sans cette séparation, le démarrage à
froid de la JVM écraserait les centiles et ferait échouer un seuil que l'application respecte en
régime établi.

**Le test n'est pas exécuté par le pipeline** : il exige un cluster déployé et dure plusieurs
minutes, ce qui ferait sortir la chaîne de sa cible de 12 minutes. Il se lance manuellement, au même
titre que `terraform apply`.

> **Limite assumée** : ces tests s'exécutent sur l'environnement de démonstration
> (**HSQLDB en mémoire**). Ils valident le comportement de la chaîne et du système sous charge —
> disponibilité pendant une mise à jour, déclenchement des alertes, tenue des seuils, position du
> point de rupture — mais **les capacités absolues devront être requalifiées après la migration
> vers PostgreSQL**. La méthode, les seuils et l'outillage, eux, resteront valables.

---

## 3. Fréquence et déclenchement

| Événement | T1–T4 lint | T5–T9 tests | T10–T13 sécurité | T14–T15 déploiement |
|---|:---:|:---:|:---:|:---:|
| *Push* sur branche de travail | ✅ | ✅ | ⚠️ SonarQube seul | ❌ |
| *Pull Request* vers `main` | ✅ | ✅ | ✅ complet | ❌ |
| *Push* / fusion sur `main` | ✅ | ✅ | ✅ complet | ✅ staging *(phase 4)* |
| Tag `v*.*.*` | ✅ | ✅ | ✅ complet | ✅ prod, **manuel** *(phase 4)* |
| Planifié — hebdomadaire | ❌ | ❌ | ✅ **T16 re-scan** | ❌ |
| **Manuel** — après une évolution d'architecture | ❌ | ❌ | ❌ | **T17 charge** |

**Justification du re-scan hebdomadaire (T16)** : une image est immuable, mais **elle devient
vulnérable avec le temps**. Une CVE publiée après la construction n'est signalée par aucun commit.
Sans exécution planifiée, elle ne serait découverte que par l'équipe Ops — c'est-à-dire trop tard,
exactement comme dans l'incident CVE initial. C'est le seul contrôle qui s'exécute **sans changement
de code**, et c'est précisément sa raison d'être.

---

## 4. Critères de validation

### 4.1 Seuils appliqués

| Contrôle | Seuil | Action si dépassé | État mesuré (17/08/2026) |
|---|---|---|---|
| ESLint | 0 **erreur** (avertissements tolérés) | ❌ Bloque | ✅ 0 erreur, 12 avertissements |
| ShellCheck | 0 défaut en `--severity=style` | ❌ Bloque | ✅ 0 défaut |
| Bits exécutables | 100 % conformes | ❌ Bloque | ✅ conforme |
| Tests unitaires | **100 %** de réussite | ❌ Bloque | ✅ 10/10 |
| Tests de scripts | **100 %** de réussite | ❌ Bloque | ✅ 27/27 |
| Test de restauration | Contenu restauré **identique** | ❌ Bloque | ✅ `diff -r` vide |
| Couverture — code nouveau | **≥ 60 %** | ❌ Bloque (quality gate) | à consolider |
| Couverture — backend global | ≥ 60 % (indicatif) | ⚠️ Avertit | ✅ **65,9 %** |
| Couverture — frontend global | ≥ 60 % (indicatif) | ⚠️ Avertit | ⚠️ **30,8 %** |
| Quality gate SonarQube | Gate « Sonar way » passée | ❌ Bloque | *cf. `docs/captures/sonarqube/`* |
| Security hotspots | **100 % revus** (revus ≠ supprimés) | ⚠️ Revue obligatoire avant release | *idem* |
| `npm audit` | 0 **CRITICAL** | ❌ Bloque | *cf. `reports/securite/`* |
| Trivy — dépendances | 0 HIGH/CRITICAL **corrigible** | ❌ Bloque | *idem* |
| Trivy — secrets | **0 détection** | ❌ Bloque **inconditionnellement** | *idem* |
| Trivy — configurations | Suivi | ⚠️ Avertit (durcissement phase 4) | *idem* |

### 4.2 Pourquoi 60 % et non 80 %

Deux arguments, l'un factuel, l'autre comportemental :

1. **L'équipe se déclare Débutante en JUnit** et le projet en est à son 2ᵉ sprint. Le seuil doit être
   un objectif atteignable, pas une aspiration.
2. **Un garde-fou inatteignable est un garde-fou qui sera désactivé** dès la première livraison
   urgente. Un seuil à 60 % réellement respecté protège infiniment mieux qu'un seuil à 80 %
   contourné par une exemption permanente.

Le seuil porte sur le **code nouveau** (*new code*) : il n'exige aucune reprise rétroactive de
l'existant, tout en garantissant que **la dette cesse de croître**. C'est le seul mécanisme qui
transforme une couverture de 30 % en trajectoire ascendante sans bloquer l'équipe.

### 4.3 Le cas particulier des security hotspots

Un *security hotspot* **n'est pas une vulnérabilité**. C'est un point du code où une décision de
sécurité a été prise et où un humain doit trancher : « ce choix est-il justifié dans ce contexte ? ».

Le critère de validation est donc **« 100 % revus »**, et non « 0 hotspot ». Exiger leur disparition
pousserait à contourner l'analyseur plutôt qu'à réfléchir. Chaque hotspot est tracé dans
`docs/captures/sonarqube/RESUME.md` avec sa catégorie, son emplacement et le verdict de revue.

---

## 5. Organisation des tests

### 5.1 Emplacement dans le dépôt

```
app/front/src/**/*.spec.ts     T5  — tests unitaires Angular (Karma + Jasmine)
app/back/src/test/java/**      T6, T7 — tests JUnit et d'intégration Spring
scripts/tests/test_commun.sh   T8  — 27 tests bash_unit des fonctions critiques
.github/workflows/ci.yml       T9  — cycle sauvegarde → restauration vérifié
reports/                       rapports produits (JUnit XML, LCOV, JaCoCo)
docs/captures/sonarqube/       preuves d'analyse conservées + historique.csv
```

### 5.2 Exécution locale — strictement identique à la CI

Le pipeline **appelle les scripts** au lieu de réimplémenter leur logique. Les commandes ci-dessous
sont donc, à la lettre, celles qu'exécute la CI :

```bash
./scripts/install-deps.sh                   # dépendances des deux composants
./scripts/run-tests.sh --sortie reports     # T5 à T7, avec couverture
bash_unit scripts/tests/test_commun.sh      # T8
./scripts/scan-securite.sh                  # T11 à T13
./scripts/sonar-analyse.sh --demarrer --arreter   # T10
```

### 5.3 Stratégie de test des scripts d'automatisation (T8)

C'est le point le plus structurant de ce plan, et il repose sur une règle de conception :

> **La logique qui DÉCIDE est séparée de la logique qui AGIT.**

`archives_a_purger()` détermine quelles sauvegardes supprimer — elle ne supprime rien. `backup.sh`
applique la décision. Conséquence : la fonction est **pure** (aucune E/S, résultat déductible des
seuls arguments) et donc testable **exhaustivement**, y compris sur les cas limites qui provoquent
les pertes de données réelles :

| Cas limite testé | Comportement exigé | Pourquoi c'est critique |
|---|---|---|
| Rétention = 0 | Ne supprime **rien** | Une variable vide ou nulle ne doit jamais valoir « tout supprimer » |
| Rétention négative | Ne supprime **rien** | Idem — garde-fou contre une variable mal typée |
| Rétention non numérique | Ne supprime **rien** | Idem |
| Nombre d'archives = rétention | Ne supprime **rien** | Erreur classique de comparaison stricte |
| Ordre d'entrée quelconque | Résultat **identique** | La fonction trie elle-même ; sinon `find` pourrait faire supprimer les archives récentes |
| Liste vide | Aucune erreur | Robustesse au premier lancement |

**Les tests sont écrits pour les cas qui détruisent des données, pas pour le cas nominal.**

Deux régressions réelles sont par ailleurs couvertes, l'une et l'autre issues d'incidents constatés :
- `attribut_xml()` — un attribut JUnit absent doit valoir `0`, jamais une chaîne vide (défaut qui
  faisait échouer un job alors que tous les tests passaient) ;
- vérification des bits exécutables — `gradlew` versionné en `644` faisait échouer le build en
  `exit 126`, sans aucun signe sur un poste Windows.

---

## 6. Gestion des données de test

| Aspect | Choix | Motif |
|---|---|---|
| Base de données | **HSQLDB en mémoire**, réinitialisée à chaque exécution | Isolation totale, aucun état résiduel entre exécutions |
| Jeu de données | Fixtures `spring-boot-data-fixtures` chargées au démarrage | Fourni par l'application, déterministe |
| Données personnelles | **Aucune donnée réelle** — uniquement des données fictives | MicroCRM manipule des personnes et organisations : utiliser des données réelles en test serait un manquement RGPD |
| Isolation | Chaque exécution repart d'un schéma vierge (`drop`/`create` Hibernate) | Vérifié dans les journaux de test |

> ⚠️ **Limite assumée et documentée.** Les tests s'exécutent sur HSQLDB alors que l'équipe Ops
> déclare PostgreSQL comme SGBD cible (constat A1 — divergence Dev/Ops). **Le SGBD de production
> n'est donc jamais exercé.** C'est la limite la plus importante de ce plan de tests. Elle n'est pas
> corrigée ici parce que la correction relève du développement applicatif, hors périmètre de la
> mission d'industrialisation. Elle constitue la **recommandation n°1** du rapport de performance,
> avec son chemin de migration : Testcontainers PostgreSQL en test d'intégration, puis bascule du
> profil d'exécution.

---

## 7. Suivi et exploitation des résultats

| Production | Format | Destination | Rétention |
|---|---|---|---|
| Résultats de tests | JUnit XML | Artefacts de l'exécution | 7 j |
| Couverture frontend | LCOV | SonarQube + artefacts | 7 j |
| Couverture backend | JaCoCo XML | SonarQube + artefacts | 7 j |
| Synthèse de pipeline | Markdown | Onglet Actions (résumé de job) | Durée de vie de l'exécution |
| Notification d'échec | Issue GitHub étiquetée `ci-echec` | Dépôt | Jusqu'à résolution |
| Preuves d'analyse | JSON + Markdown | `docs/captures/sonarqube/` + artefacts | 30 j / **versionné** |
| **Historique de qualité** | **CSV append-only** | `docs/captures/sonarqube/historique.csv` | **Permanent (versionné)** |

**L'historique CSV est la réponse à la contrainte du serveur éphémère.** Le tableau de bord SonarQube
disparaît avec le job ; l'historique, lui, est versionné, daté et rattaché à un commit. Il fournit la
comparaison avant/après exigée par le rapport de performance — et il est plus solide qu'une capture
d'écran, parce qu'il est comparable automatiquement.

En cas d'échec, une **issue GitHub** est ouverte automatiquement (une seule à la fois par branche,
les échecs suivants y sont ajoutés en commentaire). C'est la réponse directe à la faiblesse f9 :
aujourd'hui, la communication Dev↔Ops passe par e-mail et par oral, sans historique ni traçabilité.

---

## 8. Trajectoire d'amélioration

| Priorité | Action | Gain attendu | Prérequis |
|---|---|---|---|
| 1 | Porter la couverture **frontend** de 30,8 % à 60 % | Comble l'écart le plus important — et le plus inattendu | — |
| 2 | Couvrir les **branches** (9,5 % aujourd'hui) | La couverture de lignes masque des chemins d'exécution entiers non testés | — |
| 3 | **Testcontainers PostgreSQL** en test d'intégration | Supprime l'écart dev/prod (A1), la limite majeure de ce plan | Décision produit |
| 4 | Tests de sécurité **DAST** (OWASP ZAP) | Complète l'analyse statique par une analyse dynamique | Déploiement stabilisé |
| 5 | **Rejouer** les tests de charge sur base réelle | Requalifie les capacités absolues, aujourd'hui mesurées sur base en mémoire | Migration PostgreSQL |
| 6 | Tests de mutation (PIT) | Mesure la qualité des tests, pas seulement leur quantité | Couverture > 70 % |

**Fait notable pour le rapport de performance** : la mesure contredit la perception. L'équipe se
déclare « Bonne » en Angular et Karma, « Débutante » en Java et JUnit — or la couverture réelle est
de **30,8 % côté frontend** contre **65,9 % côté backend**. C'est exactement ce qu'un système de
mesure sert à révéler : la priorité d'amélioration n'est pas là où l'équipe la croyait.
