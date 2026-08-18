# 10 — Récapitulatif de conformité et préparation de la soutenance

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Objet** : croiser chaque critère de la fiche d'autoévaluation Option B **et** chacune des six
> questions de soutenance annoncées par le guide mentor avec un **pointeur de preuve** vérifiable
> dans le dépôt.
>
> Chaque ligne renvoie à un fichier ou à une exécution réelle. Aucune affirmation n'est laissée sans
> pièce à l'appui.

---

## Sommaire

1. [Les trois livrables](#1-les-trois-livrables)
2. [Conformité à la fiche d'autoévaluation](#2-conformité-à-la-fiche-dautoévaluation)
3. [Réponses aux six questions de soutenance](#3-réponses-aux-six-questions-de-soutenance)
4. [Questions d'approfondissement](#4-questions-dapprofondissement)
5. [Questions anti-IA](#5-questions-anti-ia)
6. [Écarts assumés](#6-écarts-assumés)

---

## 1. Les trois livrables

| Livrable | Attendu | État |
|---|---|---|
| **1. Lien vers le dépôt** | Dockerfiles fonctionnels, images dans le registre, code d'infrastructure, chaîne CI/CD, scripts, README technique | ✅ Dépôt public, images publiquement accessibles |
| **2. Documentation CI/CD** | Stratégie de tests, schémas d'architecture, plan de sécurité, plans de releases et de sauvegarde | ✅ Matière complète : documents 03 à 07 |
| **3. Rapport de performance** | Synthèse, indicateurs DORA, résultats de tests et couverture, captures du monitoring, gains et recommandations | ✅ Matière complète : document 08 et preuves |

### Vérification des images publiées

```
ghcr.io/jihatech/oc-devops-p6-orion/orion-microcrm-back:1.3.0
ghcr.io/jihatech/oc-devops-p6-orion/orion-microcrm-front:1.3.0
```

Accessibilité publique vérifiée par requête anonyme au registre : réponse HTTP 200, sans
authentification.

---

## 2. Conformité à la fiche d'autoévaluation

### 2.1 Concevoir, mettre en œuvre et gérer des pipelines CI

| Critère | Preuve |
|---|---|
| Le pipeline s'exécute **sans erreur de bout en bout** | 13 jobs verts — [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) |
| Conteneurs, scripts et fichiers d'infrastructure **présents et versionnés** | [`app/*/Dockerfile`](../app/), [`scripts/`](../scripts/), [`terraform/`](../terraform/), [`ansible/`](../ansible/), [`helm/`](../helm/) |
| Étapes de **build, test et déploiement identifiables** | 5 étapes nommées — [`03-normalisation-plan-ci.md`](03-normalisation-plan-ci.md) §3 |
| **README** décrivant structure, outils et procédures | [`README.md`](../README.md) |
| Instructions de déploiement **reproductibles** | [`README.md`](../README.md), section déploiement Kubernetes |
| Code annoté, **aucune donnée sensible exposée** | Trivy `secret` bloquant, 0 détection — [`05-plan-securite.md`](05-plan-securite.md) §4.3 |
| **Schéma d'architecture détaillé**, y compris cloud | 4 schémas + descriptions textuelles — [`06-architecture.md`](06-architecture.md) |

### 2.2 Planifier la mise en production CI/CD

| Critère | Preuve |
|---|---|
| Outils appropriés et compatibles | Comparatif de 8 familles d'outils — [`02-veille-recommandations.md`](02-veille-recommandations.md) |
| Objectifs alignés : **qualité, délais, collaboration** | Gains rattachés aux 3 objectifs — [`08`](08-rapport-performance-matiere.md) §4 |
| Plan de mise à jour et de sauvegarde **accessible, PSH comprise** | Structure hiérarchisée, tableaux simples, descriptions textuelles — [`07`](07-plan-releases-rollback-backup.md) |

### 2.3 Automatiser, orchestrer les conteneurs et déployer

| Critère | Preuve |
|---|---|
| Plan de conteneurisation et de releases détaillé | [`07`](07-plan-releases-rollback-backup.md) §2 et §3 |
| **Dockerfiles et charts Helm fonctionnels** | Images construites, déployées et vérifiées — [`captures/images/`](captures/images/) |
| **Orchestration Kubernetes** implémentée | Déploiement sur Minikube, 2 composants, 3 namespaces |
| Processus **traçables** | Historique Helm, tags immuables, changelog automatique |
| Documentation **reproductible** | Procédures pas à pas — [`captures/rollback/`](captures/rollback/) |

### 2.4 Mettre en place des mesures de sécurité (DevSecOps)

| Critère | Preuve |
|---|---|
| **Analyse statique** intégrée | SonarQube, porte bloquante — [`captures/sonarqube/`](captures/sonarqube/) |
| **Security hotspots** analysés | 0 détecté, avec explication du pourquoi — [`captures/sonarqube/README.md`](captures/sonarqube/README.md) |
| Tests de sécurité intégrés | 5 contrôles — [`05-plan-securite.md`](05-plan-securite.md) §4 |
| Sécurité **de bout en bout** | Secrets, permissions minimales, journaux — [`05`](05-plan-securite.md) §5 |
| Rapports **exploitables** | JSON et Markdown versionnés — [`captures/`](captures/) |
| **Vulnérabilités identifiées, priorisées, corrigées** | 86 vulnérabilités d'images à 0 ; 2 anomalies corrigées — [`08`](08-rapport-performance-matiere.md) §7 |
| Gains et recommandations documentés | [`08`](08-rapport-performance-matiere.md) §9 |

### 2.5 Mettre en place un système de mesure de performance

| Critère | Preuve |
|---|---|
| **Tableaux de bord configurés** | 1 tableau de bord, 5 visualisations — [`captures/elk/`](captures/elk/) |
| **Indicateurs DORA mesurés et interprétés** | 4 indicateurs sur données réelles — [`captures/dora/`](captures/dora/) |
| **Alertes** couvrant disponibilité, performance, sécurité | 3 règles actives, seuils différenciés — [`captures/elk/README.md`](captures/elk/README.md) |
| Interprétation et documentation | [`08`](08-rapport-performance-matiere.md) §5 |

### 2.6 Optimiser la disponibilité et la performance du SI

| Critère | Preuve |
|---|---|
| Propositions réalistes | 10 recommandations priorisées — [`08`](08-rapport-performance-matiere.md) §9 |
| **Comparaison avant / après** | 4 tableaux comparatifs — [`08`](08-rapport-performance-matiere.md) §3 |
| Recommandations argumentées | Bénéfice et effort pour chacune |
| Résultats appuyés par des métriques | DORA, couverture, vulnérabilités, durées |
| Rapport structuré et compréhensible | Rédigé pour une audience non technique |

### 2.7 Automatiser le processus de release avec le versioning

| Critère | Preuve |
|---|---|
| Procédures de release documentées | [`07`](07-plan-releases-rollback-backup.md) §2 |
| **Maintenance et rollback décrits** | [`07`](07-plan-releases-rollback-backup.md) §4, exécuté en 18 s |
| **Feedbacks analysés** | 6 incidents, chacun transformé en garde-fou — [`08`](08-rapport-performance-matiere.md) §8 |
| **Chaque script documenté** : but, fonctionnement, paramètres, conditions | Les 11 scripts de [`scripts/`](../scripts/) |

---

## 3. Réponses aux six questions de soutenance

Ces six questions sont annoncées par le guide mentor. Chaque réponse renvoie à une preuve.

### Question 1 — Comment le processus de release est-il déclenché, et comment gérez-vous les versions entre dev, staging et prod ?

**Réponse courte.** Une release est déclenchée **automatiquement** à chaque fusion sur `main`, et
seulement si les cinq étapes du pipeline sont vertes. La version est **déduite** des messages de
commit conventionnels : `fix` produit un correctif, `feat` une version mineure, `BREAKING CHANGE`
une version majeure.

Entre environnements, **la même image traverse les trois** : rien n'est reconstruit. Seules les
valeurs Helm changent — répliques, quotas, ressources. Un déploiement référence toujours un tag
immuable, jamais `latest`, et cette règle est **imposée techniquement** : le chart refuse de rendre
ses manifestes sans tag explicite.

| Preuve | Emplacement |
|---|---|
| Règles de versionnement | [`07`](07-plan-releases-rollback-backup.md) §2 |
| Promotion entre environnements | [`07`](07-plan-releases-rollback-backup.md) §3 |
| Garde-fou du tag obligatoire | `helm/microcrm/templates/_helpers.tpl` |
| 5 releases réellement produites | v1.0.0 à v1.3.0 |

**À montrer** : le `CHANGELOG.md` généré, et l'échec volontaire d'un `helm template` sans tag.

---

### Question 2 — En quoi votre démarche améliore-t-elle concrètement la disponibilité, la performance et la sécurité du SI ?

**Réponse courte.**

- **Disponibilité** : le déploiement progressif avec `maxUnavailable: 0` garantit qu'aucun ancien
  pod n'est retiré avant qu'un nouveau ne soit prêt. Lors de la démonstration d'échec, le service a
  répondu 200 à **toutes** les requêtes pendant que le déploiement échouait.
- **Performance** : elle est désormais **mesurée**. Les journaux sont structurés en JSON, donc
  agrégeables ; la durée de chaque requête est indexée et une alerte se déclenche sur dégradation.
- **Sécurité** : de **zéro à cinq** contrôles automatisés, et le délai de détection d'une
  vulnérabilité passe de plusieurs jours à quelques minutes.

| Preuve | Emplacement |
|---|---|
| Disponibilité pendant l'échec | [`captures/rollback/demonstration.log`](captures/rollback/demonstration.log) |
| Journaux structurés et alertes | [`captures/elk/`](captures/elk/) |
| Vulnérabilités : 86 à 0 | [`captures/images/README.md`](captures/images/README.md) |

**À montrer** : les trois requêtes à 200 pendant l'échec du déploiement.

---

### Question 3 — Si vous deviez prioriser les prochaines améliorations, lesquelles et pourquoi ?

**Réponse courte.** Trois priorités, dans cet ordre.

1. **Migrer la base de données** vers PostgreSQL. C'est le prérequis de tout le reste : aujourd'hui,
   un redémarrage efface les données, la sauvegarde de données est impossible, et les tests ne sont
   pas représentatifs.
2. **Ajouter une authentification** à l'API. Les données manipulées sont des personnes et des
   organisations : c'est un enjeu RGPD, et la faille est réelle.
3. **Monter le framework frontend** de deux versions majeures, pour résoudre les douze
   vulnérabilités acceptées avant leur date de réexamen du 30 novembre 2026.

**Pourquoi cet ordre** : la première débloque les deux autres et lève la limite majeure du plan de
sauvegarde. La deuxième traite le seul risque critique restant. La troisième est la plus coûteuse et
la moins urgente, puisque l'application n'est pas exposée publiquement.

| Preuve | Emplacement |
|---|---|
| Recommandations priorisées | [`08`](08-rapport-performance-matiere.md) §9 |
| Risques résiduels | [`05-plan-securite.md`](05-plan-securite.md) §8 |
| Acceptations datées | [`.trivyignore.yaml`](../.trivyignore.yaml) |

---

### Question 4 — Quelles mesures garantissent la fiabilité et la traçabilité de vos releases ?

**Réponse courte.** Cinq mesures.

1. **L'artefact promu est celui qui a été testé.** Les images ne sont jamais reconstruites au moment
   de la release : les tags sémantiques sont ajoutés au manifeste déjà publié. C'est le même
   artefact, au bit près.
2. **Aucune image vulnérable n'atteint le registre** : le scan Trivy se situe entre la construction
   et la publication, dans le même job.
3. **Chaîne de traçabilité ininterrompue** : commit conventionnel, version déduite, tag Git, tag
   d'image, annotation sur le déploiement. On peut remonter d'un pod en cours d'exécution jusqu'au
   commit qui l'a produit.
4. **L'historique conserve les échecs.** Un rollback Helm ne supprime rien : il crée une nouvelle
   révision. Un mauvais déploiement reste visible.
5. **Tout est épinglé** : images de base par empreinte, actions, outils. Deux constructions du même
   commit produisent le même résultat.

| Preuve | Emplacement |
|---|---|
| Promotion sans reconstruction | `.github/workflows/ci.yml`, job `release` |
| Historique Helm avec l'échec conservé | [`captures/rollback/README.md`](captures/rollback/README.md) |
| Épinglage par empreinte | `app/*/Dockerfile` |

**À montrer** : l'annotation de version sur un déploiement en cours, remontée jusqu'au commit.

---

### Question 5 — Quels défis avez-vous rencontrés et comment les avez-vous résolus ?

**Réponse courte.** Six incidents, chacun transformé en garde-fou permanent. Trois méritent d'être
racontés.

**Le contrôle de sécurité échouait quand il ne trouvait rien.** Sous `set -o pipefail`, un `grep`
sans correspondance renvoie un code d'erreur : « zéro vulnérabilité détectée » faisait donc échouer
le job. **Le résultat recherché provoquait l'échec.** ShellCheck ne détecte pas cette classe
d'erreur — seule l'exécution la révèle. Le comptage a été isolé dans une fonction couverte par
quatre tests.

**Un fichier de lancement versionné sans droit d'exécution.** Le poste de développement est sous
Windows, qui ne porte pas cette information : le défaut était strictement invisible en local et n'est
apparu qu'au premier build Linux. Un contrôle a été ajouté à l'étape de lint — et **deux phases plus
tard, il a rattrapé exactement la même erreur sur un autre fichier**.

**Un calcul d'indicateur DORA annonçant 236 déploiements par semaine.** Le code était juste ; c'est
la définition de la période qui ne l'était pas. Le chiffre était mathématiquement exact, flatteur, et
complètement faux. Le script marque désormais comme non représentatif tout résultat portant sur moins
de quatorze jours.

**Le point commun** : cinq de ces six incidents étaient **invisibles sur le poste** et n'ont été
révélés que par l'automatisation. C'est l'argument le plus concret en faveur de la démarche chez
Orion, où tout est aujourd'hui exécuté à la main.

| Preuve | Emplacement |
|---|---|
| Les 6 incidents et leurs garde-fous | [`08`](08-rapport-performance-matiere.md) §8 |
| Journal détaillé par phase | [`JOURNAL_IA.md`](JOURNAL_IA.md) |

---

### Question 6 — En cas d'échec de déploiement, quelle est la procédure de rollback et comment est-elle automatisée ?

**Réponse courte.** Il y a **deux barrières successives**, et c'est le point important.

La première est un **Job de migration** exécuté avant toute modification. S'il échoue, le
déploiement s'arrête et **aucun pod n'est remplacé** : l'état du cluster est inchangé, il n'y a rien
à annuler. Le meilleur rollback est celui qu'on n'a pas besoin de faire.

La seconde est constituée des **sondes de démarrage et de disponibilité**. Un pod qui ne devient
jamais prêt n'est jamais inscrit dans le Service : il ne reçoit aucun trafic, et l'ancien continue
de servir.

Si un retour arrière est nécessaire, `scripts/rollback.sh` l'automatise : il détermine la **dernière
révision saine** — jamais une révision en échec —, exécute le retour, puis **vérifie par un test
HTTP** que le service répond. Une release marquée « deployed » dont le service ne répond pas n'est
pas un rollback réussi.

**Résultat mesuré** : 18 secondes, vérification comprise, sans aucune interruption de service.

| Preuve | Emplacement |
|---|---|
| Démonstration complète | [`captures/rollback/README.md`](captures/rollback/README.md) |
| Journal d'exécution | [`captures/rollback/demonstration.log`](captures/rollback/demonstration.log) |
| Trace du rollback | [`captures/rollback/trace-rollback.log`](captures/rollback/trace-rollback.log) |
| Migrations bloquantes | [`captures/rollback/migrations.log`](captures/rollback/migrations.log) |

**À montrer** : le tableau comparant les deux barrières — détection par sondes contre détection par
le Job de migration.

---

## 4. Questions d'approfondissement

Ces questions ne peuvent pas justifier un refus, mais méritent une réponse préparée.

### FinOps et GreenOps

| Levier | Économie | Effet environnemental |
|---|---|---|
| Éteindre la recette hors heures ouvrées | Environ 60 % des nœuds de recette | 128 heures d'inactivité évitées sur 168 |
| Instances réservées | 30 à 40 % | Meilleur taux d'utilisation du matériel |
| Images minimales | Stockage et transfert | Le frontend pèse 111 Mo, non 300 |
| Cache de dépendances | Durée du pipeline | Moins de calcul et de transfert réseau |
| Annulation des exécutions obsolètes | Minutes de calcul | Déjà en place : `cancel-in-progress` |

Deux mesures sont **déjà appliquées** : l'annulation automatique des exécutions rendues obsolètes par
un nouveau commit, et le cache des dépendances.

### Multi-cloud et hybride

Traité en détail dans [`09-evolution-cloud.md`](09-evolution-cloud.md) §8. La position défendue :
**ne pas viser le multi-cloud** pour une équipe de deux personnes à l'exploitation, mais **maintenir
la portabilité** en s'appuyant sur Kubernetes et Helm — ce qui est déjà le cas — et en isolant les
parties spécifiques au fournisseur dans des modules distincts.

---

## 5. Questions anti-IA

Le guide mentor prévoit des questions du type « comment avez-vous fait ? », « quelle méthodologie ? »,
« quelles étapes ? ».

**La réponse est [`JOURNAL_IA.md`](JOURNAL_IA.md)**, tenu à chaque phase. Il documente la démarche,
les décisions avec leurs alternatives écartées, les incidents avec leur diagnostic, et l'usage réel
de l'IA — assumé comme assistant de rédaction, jamais comme source de vérité.

Trois éléments établissent que le travail a été fait, et non généré :

1. **Chaque constat de l'audit cite un fichier et une ligne.** La divergence entre les équipes sur le
   choix du SGBD, par exemple, ne se déduit pas d'un savoir général : elle vient du croisement de
   deux sondages et d'une ligne de `build.gradle`.
2. **Les incidents sont racontés avec leur diagnostic**, y compris les erreurs de méthode — un test
   de contrôle faux qui m'a fait accuser à tort un outil, une empreinte d'image inventée que j'ai
   remplacée par la vraie avant toute construction.
3. **Les chiffres proviennent d'exécutions réelles**, archivées dans [`captures/`](captures/) :
   analyses SonarQube, scans d'images, rollback chronométré, agrégations ELK, indicateurs DORA.

---

## 6. Écarts assumés

Ces écarts sont **volontaires et documentés**. Les annoncer vaut mieux que de les laisser découvrir.

| Écart | Motif | Où c'est écrit |
|---|---|---|
| **GitHub plutôt que GitLab** | La fiche indique « GitLab ou équivalent » ; validé par le mentor le 31/07/2026. Table de correspondance fournie | [`02`](02-veille-recommandations.md) §10 |
| **SonarQube en conteneur plutôt que SonarCloud** | Aucune dépendance externe, aucun secret ; l'évaluateur peut tout relancer | [`JOURNAL_IA.md`](JOURNAL_IA.md), phase 3 |
| **Minikube plutôt qu'un cluster managé** | Environ 180 € par mois sans bénéfice hors production ; migration documentée et chiffrée | [`09`](09-evolution-cloud.md) §1 |
| **Base de données non migrée** | Développement applicatif, hors périmètre d'industrialisation | [`08`](08-rapport-performance-matiere.md) §9 |
| **API sans authentification** | Même motif ; signalée comme risque critique | [`05`](05-plan-securite.md) §8 |
| **12 vulnérabilités acceptées** | Correctif à deux versions majeures ; acceptations datées au 30/11/2026 | [`.trivyignore.yaml`](../.trivyignore.yaml) |
| **Alertes sans canal de notification** | Nécessiterait des credentials externes ; configuration documentée | [`captures/elk/README.md`](captures/elk/README.md) |
| **Politiques réseau non appliquées** | Minikube avec le pilote Docker ne les applique pas ; correctes et prêtes pour un cluster managé | `terraform/modules/namespace-applicatif/main.tf` |
| **Couverture à 37,4 %** | L'application est arrivée sans tests exploitables ; assumée comme axe d'amélioration chiffré | [`08`](08-rapport-performance-matiere.md) §6 |
