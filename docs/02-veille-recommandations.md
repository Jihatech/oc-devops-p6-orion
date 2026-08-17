# 02 — Veille technologique et recommandations

> **Entrée** : conclusions de `docs/01-audit-swot.md`.
> **Règle de sélection** : ne sont retenues que les solutions **réalistes pour Orion** — 4 Dev + 2 Ops,
> application pas encore en production, compétences cartographiées par les sondages, budget non illimité.
> Toute solution écartée l'est **explicitement et avec justification**, afin de pouvoir défendre le choix.
> Le guide mentor est formel : *« il n'est pas nécessaire d'implémenter toutes les recommandations »* —
> la valeur est dans la **priorisation argumentée**, pas dans l'exhaustivité.

---

## 0. Méthode d'évaluation

Chaque famille d'outils est évaluée sur 5 critères, notés ⭐ à ⭐⭐⭐ :

| Critère | Question posée |
|---|---|
| **Adéquation compétences** | L'équipe sait-elle déjà s'en servir, d'après les sondages ? |
| **Coût** | Licence + infrastructure + temps d'exploitation |
| **Effort d'intégration** | Charge de mise en place initiale |
| **Gain sur les goulots** | Lève-t-il un goulot G1–G6 ou une lacune S1–S9 identifiés à l'audit ? |
| **Risque** | Verrouillage fournisseur, maintenance, dépendance à une personne |

---

## 1. Plateforme CI/CD

### Comparatif

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **GitLab CI** (cité par la mission) | ⭐⭐ | Gratuit, **quota 400 min/mois** sur SaaS | ⭐⭐ | ⭐⭐⭐ | Quota à surveiller ; runner à auto-héberger sinon |
| **GitHub Actions** | ⭐⭐⭐ | **Gratuit et illimité sur dépôt public** | ⭐⭐⭐ | ⭐⭐⭐ | Faible ; écosystème d'actions très large |
| **Jenkins** | ⭐ | Gratuit mais **serveur à héberger et maintenir** | ⭐ | ⭐⭐ | **Élevé** : charge d'exploitation pour 2 Ops |
| **Azure DevOps** | ⭐ | Gratuit (limité) | ⭐⭐ | ⭐⭐ | Écosystème étranger aux deux équipes |

### ✅ Recommandation : **GitHub Actions**

**Justification.** Le choix se joue entre GitLab CI et GitHub Actions ; Jenkins est écarté d'emblée
(un serveur à administrer pour **2 Ops déjà saturés par le déploiement manuel** — f10 — serait un
transfert de charge, pas une amélioration).

Arguments retenus pour GitHub Actions :

1. **Aucun quota de minutes sur dépôt public**, là où GitLab SaaS plafonne à 400 min/mois. Or ce
   pipeline exécutera builds Gradle, tests Karma, analyse Sonar et scan Trivy à chaque *push* : le
   quota serait le facteur limitant du projet.
2. **Registre d'images intégré (GHCR)** authentifié par le jeton natif du pipeline — cela répond
   directement à la demande Ops (O1) **sans aucun secret externe à gérer** (atténue S5/M3).
3. **`GITHUB_TOKEN` éphémère et à permissions granulaires** : jeton régénéré à chaque exécution,
   permissions déclarées workflow par workflow (`contents: read`, `packages: write`). Modèle de secret
   supérieur à un jeton de registre longue durée.
4. **Écosystème d'actions officielles** (`actions/cache`, `aquasecurity/trivy-action`,
   `SonarSource/sonarqube-scan-action`) qui réduit l'effort d'intégration — critère décisif pour une
   équipe sans expérience CI avancée.

> ⚠️ **Point de vigilance assumé.** L'énoncé de mission cite GitLab CI, mais la **fiche
> d'autoévaluation Option B indique « GitLab (ou équivalent) »**, et le choix GitHub a été
> **explicitement validé par le mentor en session enregistrée du 31/07/2026** (« bien au contraire »).
> Les concepts évalués — étapes, artefacts, quality gate, registre, sécurité — sont strictement
> identiques. **Une table de correspondance GitHub Actions ↔ GitLab CI est fournie en §10** pour
> démontrer en soutenance la portabilité complète de la démarche.

---

## 2. Analyse statique de code (demande explicite de l'équipe Dev)

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **SonarQube Community** (service container en CI) | ⭐⭐ | Gratuit, mais **serveur + PostgreSQL à faire vivre** | ⭐⭐ | ⭐⭐⭐ | Historique perdu si serveur éphémère |
| **SonarCloud** (moteur SonarQube en SaaS) | ⭐⭐⭐ | **Gratuit sur dépôt public** | ⭐⭐⭐ | ⭐⭐⭐ | Analyse hébergée chez l'éditeur |
| ESLint / Checkstyle seuls | ⭐⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐ | Ne couvrent **ni** les vulnérabilités **ni** les security hotspots |
| Snyk Code | ⭐ | Gratuit limité | ⭐⭐ | ⭐⭐ | Quota, et **ne remplace pas l'exigence SonarQube** |

### ✅ Recommandation : **SonarQube — via SonarCloud**, en complément d'ESLint et de ShellCheck

**Justification.** L'équipe Dev demande textuellement « des outils d'analyse statique et d'aide à la
conception pour éviter d'intégrer des mauvaises pratiques ». Avec un niveau **Débutant en Java, Spring
Boot, Gradle et JUnit**, aucune revue de code interne ne peut jouer ce rôle : SonarQube devient le
**filet de sécurité de compétence** de l'équipe (lève G6).

Choix **SonarCloud plutôt que serveur Community auto-hébergé** :

| Critère | Community en service container | SonarCloud |
|---|---|---|
| Historique des analyses | **Perdu** à chaque job (conteneur éphémère) | **Conservé** → suivi de la dette dans le temps |
| Décoration des Pull Requests | À câbler manuellement | Native |
| Charge d'exploitation | Serveur + base à maintenir | Nulle |
| Coût | Gratuit (mais CPU/RAM du runner) | Gratuit sur dépôt public |
| Quality gate | Oui | Oui |
| Security hotspots | Oui | Oui |

La mesure de la **tendance** de la dette est l'objectif même du projet (rapport de performance,
comparaison avant/après). Un serveur éphémère la rendrait impossible. SonarCloud exécute le **même
moteur d'analyse SonarQube** : l'exigence « SonarQube obligatoire » est pleinement satisfaite.

**Compléments retenus, non redondants** :
- **ESLint** (front) et **ShellCheck** (scripts Bash) : détection **rapide et locale**, exécutée avant
  Sonar pour un retour en secondes plutôt qu'en minutes.
- **JaCoCo** (back) et **karma-coverage au format lcov** (front) : sans rapport de couverture,
  SonarQube n'affiche aucune métrique de tests (comble C6 et C7).

---

## 3. Sécurité des images de conteneurs (demande explicite de l'équipe Ops)

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **Trivy** | ⭐⭐⭐ **déjà utilisé par l'Ops** | Gratuit, open source | ⭐⭐⭐ | ⭐⭐⭐ | Très faible |
| Grype | ⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐⭐⭐ | Outil supplémentaire à apprendre |
| Snyk Container | ⭐ | Freemium, quota | ⭐⭐ | ⭐⭐ | Dépendance commerciale |
| Docker Scout | ⭐⭐ | Freemium | ⭐⭐ | ⭐⭐ | Lié à l'écosystème Docker Hub — que l'Ops veut quitter |

### ✅ Recommandation : **Trivy dans la CI** (image + système de fichiers + configuration)

**Justification — c'est la recommandation à plus fort retour du projet.** L'équipe Ops utilise
**déjà Trivy**, mais **après** réception de l'image : c'est exactement le mécanisme qui a retardé le
premier déploiement (incident CVE, §1.2 de l'audit). Le déplacer dans le pipeline :

- **coût d'apprentissage nul** — l'outil est connu, les résultats sont déjà interprétés par l'Ops ;
- **supprime le cycle « retour à l'envoyeur »** cité comme irritant n°1 par l'Ops (lève G1) ;
- **rend le contrôle bloquant et systématique** au lieu d'humain et ponctuel ;
- **inverse la responsabilité** : le Dev voit la CVE dans son pipeline, à l'instant où il l'introduit.

Trois usages de Trivy sont retenus : `image` (CVE de l'image publiée), `fs` (dépendances applicatives),
`config` (mauvaises configurations Dockerfile/K8s). Stratégie de blocage : **`CRITICAL`/`HIGH` bloquant
sur les vulnérabilités corrigibles**, le reste en rapport — un seuil « zéro CVE » serait ingérable et
serait contourné dès la première urgence.

> Cette recommandation a été **validée par le mentor** en session du 31/07/2026.

---

## 4. Registre d'images (demande explicite de l'équipe Ops)

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **GHCR** | ⭐⭐⭐ | Gratuit (public) | ⭐⭐⭐ auth. native CI | ⭐⭐⭐ | Faible |
| Harbor auto-hébergé | ⭐ | Gratuit mais serveur à administrer | ⭐ | ⭐⭐⭐ | **Élevé** pour 2 Ops |
| Docker Hub | ⭐⭐ | Freemium, **rate limits** | ⭐⭐⭐ | ⭐ | **Explicitement rejeté par l'Ops** |
| AWS ECR / Azure ACR | ⭐ | Payant | ⭐⭐ | ⭐⭐⭐ | Prématuré (pas encore de cloud) |

### ✅ Recommandation : **GHCR** (GitHub Container Registry)

L'Ops demande « un dépôt d'images interne à l'entreprise pour ne plus être dépendant de plateformes
externes comme Docker Hub ». **Harbor** répondrait à la lettre de la demande, mais ajouterait un serveur
à administrer à une équipe de 2 personnes déjà en surcharge (f10) : le remède serait pire que le mal.

GHCR répond à **l'intention réelle** — sortir de Docker Hub, de ses *rate limits* et de sa dépendance
tierce (M6) — avec authentification native par `GITHUB_TOKEN` (donc **aucun secret longue durée**),
contrôle d'accès aligné sur le dépôt, et rétention gérée. **Harbor reste la cible naturelle** si Orion
exige un jour un registre strictement on-premise : la démarche (tags sémantiques, scan avant push) est
identique, seule l'URL du registre change. Ce point est documenté dans `docs/09-evolution-cloud.md`.

---

## 5. Orchestration et déploiement

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **Kubernetes (Minikube) + Helm** | ⭐⭐ | Gratuit, local | ⭐⭐ | ⭐⭐⭐ **rollback natif** | Courbe d'apprentissage |
| Docker Compose | ⭐⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐ | Ni rollback, ni montée en charge, ni sondes |
| Kubernetes managé (EKS/AKS) | ⭐ | **Payant** (~70 €/mois + nœuds) | ⭐⭐ | ⭐⭐⭐ | Coût réel pour une app hors production |
| Nomad | ⭐ | Gratuit | ⭐⭐ | ⭐⭐ | Écosystème marginal, compétence rare |

### ✅ Recommandation : **Kubernetes sur Minikube + charts Helm**, avec plan d'évolution cloud

**Justification.** Docker Compose serait le choix du moindre effort et correspondrait au niveau
« Docker Bon » des deux équipes — mais il **ne fournit ni rollback, ni sondes de santé, ni gestion de
secrets par environnement**. Or **f8 (aucun rollback) est l'une des faiblesses critiques de l'audit**,
et la procédure de rollback est un attendu explicite de la mission.

**`helm rollback` répond à lui seul à un goulot majeur** : retour à la version N-1 en une commande,
versionné, traçable, testable. C'est le gain décisif.

**Minikube plutôt que cloud managé** : l'application n'est pas en production, l'objectif est de
**démontrer une maîtrise de l'orchestration**, pas d'exploiter un cluster. Un EKS coûterait ~70 €/mois
de plan de contrôle plus les nœuds, sans aucun bénéfice pédagogique ou opérationnel supplémentaire à ce
stade. Les manifestes Helm sont **identiques à 95 %** entre Minikube et un cluster managé.

> ⚠️ **Ce choix n'est défendable qu'accompagné d'un plan d'évolution cloud concret** (auth OIDC,
> registre, ingress, storage classes, secrets managés, coûts) — c'est l'objet de
> `docs/09-evolution-cloud.md`, et la question est systématiquement posée en soutenance.

---

## 6. Infrastructure as Code

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **Terraform** | ⭐⭐ | Gratuit | ⭐⭐ | ⭐⭐⭐ | Faible ; état à gérer |
| **Ansible** | ⭐⭐⭐ **« Bon » chez l'Ops** | Gratuit | ⭐⭐⭐ | ⭐⭐⭐ | Très faible |
| Pulumi | ⭐ | Freemium | ⭐⭐ | ⭐⭐ | Compétence absente de l'équipe |
| Scripts Bash seuls | ⭐⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐ | Ni idempotence, ni état, ni convergence |

### ✅ Recommandation : **Terraform (provisionnement) + Ansible (configuration)**, répartition explicite

Les deux outils sont exigés par la mission ; l'enjeu est d'**éviter le recouvrement**, faute de quoi la
frontière devient arbitraire — et c'est une question de soutenance classique. Répartition retenue :

| Outil | Responsabilité | Périmètre concret chez Orion |
|---|---|---|
| **Terraform** | **Ce qui existe** — cycle de vie des ressources, état désiré | Namespaces K8s, quotas, releases Helm, réseaux et volumes Docker |
| **Ansible** | **Ce qui est configuré dedans** — convergence, tâches ordonnées | Prérequis machine, démarrage Minikube, déploiement applicatif, back-up, restauration |

**Ansible capitalise sur un acquis fort** (« Bon » chez l'Ops, et déjà utilisé au quotidien) : les
playbooks seront relus et maintenus par ceux qui les exploitent. **Terraform est le seul apprentissage
réel** — il est justifié par sa portabilité : le même code, avec un autre *provider*, décrit demain un
VPC AWS (voir `docs/09-evolution-cloud.md`).

---

## 7. Observabilité et mesure de performance

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **ELK (Elasticsearch + Logstash/Filebeat + Kibana)** | ⭐⭐ | Gratuit, **gourmand en RAM** | ⭐⭐ | ⭐⭐⭐ | Consommation mémoire locale |
| Prometheus + Grafana | ⭐⭐ | Gratuit | ⭐⭐ | ⭐⭐⭐ | Orienté **métriques**, pas logs |
| Loki + Grafana | ⭐⭐ | Gratuit, **plus léger qu'ELK** | ⭐⭐⭐ | ⭐⭐⭐ | Écosystème d'alerting moins riche |

### ✅ Recommandation : **stack ELK**, dimensionnée pour un poste de développement

ELK est explicitement attendu par la mission et le guide mentor. Le besoin d'Orion est d'abord un
besoin de **logs centralisés** — aujourd'hui inexistants (S7) — plus que de métriques temps réel :
ELK est donc fonctionnellement le bon choix, et non un choix par défaut.

**Réserve assumée** : Elasticsearch est gourmand (≈ 2 Go de RAM au minimum réaliste). Sur un poste
partagé avec Minikube, la stack sera **dimensionnée explicitement** (nœud unique, limites de heap,
politique de rétention courte). Si la contrainte devenait bloquante, **Loki serait l'alternative** —
la démarche (collecte, indexation, tableaux de bord, alertes) reste inchangée.

**Métriques DORA** : aucun outil clé en main gratuit ne couvre correctement les 4 indicateurs. Un
**script Python interrogeant l'API GitHub** (`scripts/dora-metrics.py`) est retenu — il calcule
*lead time*, *deployment frequency*, *change failure rate* et *MTTR* à partir de la source de vérité
(commits, exécutions de workflow, releases), avec export CSV/ELK. Sur mesure, transparent,
**explicable en soutenance** — et c'est là son principal mérite face à une boîte noire SaaS.

---

## 8. Versionnement et releases

| Solution | Adéquation | Coût | Intégration | Gain | Risque |
|---|---|---|---|---|---|
| **semantic-release + Conventional Commits** | ⭐⭐ | Gratuit | ⭐⭐ | ⭐⭐⭐ | Exige une discipline de commit |
| Tags manuels | ⭐⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐ | Erreur humaine, oublis, incohérences |
| release-please | ⭐⭐ | Gratuit | ⭐⭐⭐ | ⭐⭐ | Passe par une PR intermédiaire |

### ✅ Recommandation : **semantic-release** piloté par les Conventional Commits

**Justification.** L'audit relève l'absence totale de traçabilité (f4) : `0.0.1-SNAPSHOT` figé, aucun
tag, la question « quelle version tourne sur la démo ? » est aujourd'hui sans réponse. Les tags manuels
reproduiraient l'erreur humaine que le projet cherche justement à éliminer.

semantic-release rend le versionnement **déductible du contenu des commits** : `fix:` → *patch*,
`feat:` → *mineure*, `BREAKING CHANGE` → *majeure*. La version, le changelog, le tag Git et les tags
d'images sont produits **par la même source de vérité**. La discipline de commit exigée est un
bénéfice collatéral pour une équipe qui n'a pas encore figé ses conventions (2ᵉ sprint).

---

## 9. Recommandations **écartées** (et pourquoi)

Cette section est délibérée : le guide mentor rappelle qu'il ne faut **pas** tout implémenter. Ces
options ont été étudiées puis rejetées pour Orion **à ce stade**.

| Solution | Pourquoi c'était tentant | ❌ Pourquoi écartée |
|---|---|---|
| **Migration HSQLDB → PostgreSQL** | Corrige l'écart dev/prod A1, la faiblesse la plus structurante | **Modifie le code applicatif fourni**, hors périmètre de la mission (industrialiser, pas réécrire). **Documentée comme recommandation n°1 d'amélioration continue** dans le rapport de performance, avec le chemin de migration. |
| **Ajout de `spring-boot-starter-security`** (S2/A4) | Faille critique : API CRM sans authentification | Même raison : développement applicatif. **Signalée comme risque critique** au rapport, avec correctif proposé. La CI la **détecte** (Sonar), elle ne la corrige pas. |
| **Harbor** (registre auto-hébergé) | Répond littéralement au « registre interne » | Serveur supplémentaire à administrer pour 2 Ops en surcharge (f10). GHCR répond à l'intention. Reclassé en cible d'évolution. |
| **Cluster K8s managé (EKS/AKS)** | Plus « professionnel », réaliste production | Coût réel (~70 €/mois + nœuds) sans bénéfice pour une app hors production. **Minikube + plan de migration documenté** offre la même démonstration de maîtrise. |
| **ArgoCD / GitOps** | État du cluster réconcilié en continu, rollback Git | Sur-ingénierie à ce stade : une brique de plus à exploiter pour un seul environnement local. **Retenu comme évolution** une fois le cloud en place. |
| **Tests E2E Cypress/Playwright** | Couverture fonctionnelle bout en bout | Coût de mise en place et de maintenance élevé face au périmètre fonctionnel minimal de MicroCRM (CRUD). Les tests unitaires + un test de fumée post-déploiement offrent un bien meilleur rapport valeur/effort. |
| **Vault (HashiCorp)** | Gestion des secrets de niveau entreprise | GitHub Secrets + Secrets K8s suffisent au périmètre. Vault s'imposera avec le multi-environnement cloud. |
| **DAST (OWASP ZAP)** | Complète le SAST par une analyse dynamique | Nécessite un environnement déployé et stable dans la CI. **Recommandé en amélioration continue**, une fois la chaîne de déploiement fiabilisée. |
| **Tests de charge (k6 / JMeter)** | Cité en optimisation cloud par la mission | Peu de sens sur HSQLDB en mémoire, sur poste local : les chiffres ne seraient pas représentatifs. Documenté comme prérequis « après migration PostgreSQL ». |

---

## 10. Table de correspondance GitHub Actions ↔ GitLab CI

*Fournie pour démontrer que la démarche est indépendante de la plateforme (argumentaire de soutenance).*

| Concept | GitLab CI | GitHub Actions |
|---|---|---|
| Fichier de définition | `.gitlab-ci.yml` | `.github/workflows/ci.yml` |
| Étape | `stages:` / `stage:` | `jobs:` + `needs:` |
| Exécuteur | `image:` (runner Docker) | `runs-on:` + `container:` |
| Artefacts | `artifacts:paths` | `actions/upload-artifact` |
| Cache | `cache:key/paths` | `actions/cache` |
| Variables masquées | Variables CI/CD protégées | GitHub Secrets |
| Registre intégré | GitLab Container Registry | GHCR |
| Jeton natif | `CI_JOB_TOKEN` | `GITHUB_TOKEN` |
| Environnements | `environment:` | `environment:` |
| Déclencheurs | `rules:` / `only/except` | `on:` + `if:` |
| Modèles réutilisables | `include:` / templates | Actions et workflows réutilisables |

---

## 11. Synthèse : priorisation MoSCoW

| Priorité | Recommandation | Goulot / lacune levés | Effort |
|---|---|---|---|
| **MUST** | Pipeline CI GitHub Actions structuré en 5 étapes | C1, C9, G5 | M |
| **MUST** | **SonarQube (SonarCloud)** + quality gate + security hotspots | S1, f7, G6 | M |
| **MUST** | **Trivy** (image + fs + config) dans la CI | **S1, S3, G1, M1, M4** | **S** |
| **MUST** | Build + push automatisés vers **GHCR** avec tags sha + semver | **f2, f4, G2, G4, M6** | M |
| **MUST** | Scripts Bash/Python documentés (deps, tests, déploiement, back-up, notification) | f3, f8, G3 | M |
| **MUST** | Épinglage strict de toutes les images de base et versions d'outils | **S3, f5, M4** | **S** |
| **MUST** | Secrets exclusivement en GitHub Secrets, permissions minimales des workflows | S5, M3 | S |
| **SHOULD** | Kubernetes + Helm avec `helm rollback` testé | **f8, G3** | L |
| **SHOULD** | Couverture de tests (JaCoCo + lcov) remontée à Sonar | C6, C7 | S |
| **SHOULD** | Terraform + Ansible intégrés au pipeline | f3, G3 | L |
| **SHOULD** | Stack ELK + tableaux de bord + alertes | **S7** | L |
| **SHOULD** | Métriques DORA automatisées | f9, pilotage | M |
| **SHOULD** | semantic-release + Conventional Commits | **f4, S9** | M |
| **SHOULD** | Conteneurs non-root + `HEALTHCHECK` + `EXPOSE` corrigé | S4, S6, A5, A10 | S |
| **COULD** | Sauvegarde/restauration automatisée et **testée** | f8, S8 | M |
| **COULD** | Plan d'évolution cloud documenté et chiffré | M7, pérennité | M |
| **WON'T** *(this time)* | PostgreSQL, authentification API, Harbor, ArgoCD, Vault, DAST, E2E, tests de charge | *cf. §9* | — |

**Séquencement retenu** : les *MUST* traitent d'abord la **cause démontrée de l'incident** (sécurité en
aval, manuelle) et l'**absence de traçabilité de l'artefact**, parce qu'ils bloquent aujourd'hui la mise
en production. Les *SHOULD* construisent ensuite la **réversibilité** (rollback, back-up) et la
**visibilité** (ELK, DORA), qui deviennent indispensables au moment exact où l'application passera en
production.

➡️ **Suite** : `docs/03-normalisation-plan-ci.md` — structure cible du pipeline, ordre d'exécution
argumenté, schéma de workflow.
