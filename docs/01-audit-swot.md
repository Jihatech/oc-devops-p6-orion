# 01 — Audit du processus CI existant chez Orion (SWOT)

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Sources** : sondage équipe Dev + sondage équipe Ops (`docs/contexte/`), et **analyse directe du code
> fourni** (`app/.gitlab-ci.yml`, `app/Dockerfile`, `app/back/build.gradle`, `app/front/package.json`,
> `app/front/karma.conf.js`).
> **Périmètre** : application Full-Stack **MicroCRM** (Angular 17 + Spring Boot 3), 2ᵉ sprint, **jamais
> déployée en production** — uniquement sur un environnement de démonstration.

---

## 1. État des lieux factuel

### 1.1 Les équipes

| | **Dev** | **Ops** |
|---|---|---|
| Membres | Roubina (lead), Sylvain (senior), Temim (junior), Josefina (stagiaire) | Nico (lead), Maïa (senior) |
| Effectif | 4 | 2 |
| Points forts déclarés | TypeScript/Angular **Bon**, NPM **Bon**, Karma **Bon**, Docker **Bon** | Bash **Très bon**, Ansible **Bon**, Apt **Bon**, TestInfra **Bon**, BashUnit **Bon**, Debian **Bon**, Docker **Bon** |
| Points faibles déclarés | Java/Spring Boot **Débutant**, Gradle **Débutant**, JUnit **Débutant**, HyperSQL **Débutant** | PostgreSQL **Moyen** |
| Demande explicite | Outils d'**analyse statique** et d'aide à la conception, pour « éviter d'intégrer des mauvaises pratiques dans le pipeline » | **Dépôt d'images interne** (sortir de Docker Hub) + **analyse de sécurité des images en amont**, pour supprimer les « retours à l'envoyeur » |

> **Lecture** : les deux équipes formulent d'elles-mêmes le besoin auquel répond ce projet. L'équipe Dev
> demande SonarQube sans le nommer ; l'équipe Ops demande GHCR + Trivy sans les nommer. Les
> recommandations de ce projet ne sont donc pas imposées : elles sont **la réponse outillée à une
> demande interne existante**.

### 1.2 Le cycle actuel

**Côté Dev** (7 étapes) : réception des évolutions → chiffrage/priorisation avec le PO → développement →
démo mi-itération → intégration des retours → correctifs bloquants → **génération manuelle des images**
et envoi des références à l'Ops par e-mail.

**Côté Ops** (3 étapes) : réception d'un numéro de version → **analyse Trivy manuelle** de l'image →
**déploiement manuel via commandes `docker`** sur l'environnement de démonstration.

**Canaux d'échange Dev↔Ops** : e-mail et communication en direct (vis-à-vis). Aucun canal outillé,
aucune traçabilité.

**Incident déjà survenu** : des **CVE présentes dans l'image** ont été détectées *après* transmission à
l'Ops, ce qui a **retardé le premier déploiement** sur l'environnement de démonstration. C'est le
symptôme central : le contrôle de sécurité est effectué **trop tard, par la mauvaise équipe, à la main**.

### 1.3 La chaîne CI existante — analyse technique

Le fichier `app/.gitlab-ci.yml` fourni compte **34 lignes et 2 étapes** (`test`, `build`) :

```yaml
stages: [test, build]
test-front:  image: cypress/browsers:latest  → npm ci + ng test
test-back:   image: gradle:jdk17             → ./gradlew test
build-front: image: node                     → npm ci + ng build --optimization
build-back:  image: gradle:jdk17             → ./gradlew build
```

Constats vérifiés dans le dépôt :

| # | Constat | Preuve | Impact |
|---|---|---|---|
| C1 | **Aucune étape de sécurité** dans la CI (ni SAST, ni scan de dépendances, ni scan d'image) | `.gitlab-ci.yml` : 2 stages seulement | Cause directe de l'incident CVE |
| C2 | **Aucune image Docker construite ni publiée par la CI**, alors que les images **sont** l'artefact de livraison (3 images attendues) | Le `Dockerfile` n'est jamais appelé dans le pipeline | Le livrable réel échappe totalement à l'automatisation |
| C3 | **Aucun artefact conservé** (`artifacts:` absent) | `.gitlab-ci.yml` | Le JAR et le bundle Angular sont détruits en fin de job ; impossible de rejouer une version |
| C4 | **Images de base non épinglées** : `node`, `cypress/browsers:latest` | `.gitlab-ci.yml` l. 6 et 22 | Builds non reproductibles, casse aléatoire hors de tout changement de code |
| C5 | **Aucun cache** de dépendances (`npm`, Gradle) | `.gitlab-ci.yml` | `npm ci` exécuté 2× par pipeline ; durée et coût de runner inutiles |
| C6 | **Aucune mesure de couverture exploitée** : `karma-coverage` est installé et configuré, mais en `html` + `text-summary` uniquement, et jamais activé en CI | `front/karma.conf.js` l. 30-34 ; `package.json` l. 33 | Pas de format `lcov` → aucune donnée exploitable par un outil de qualité |
| C7 | **Aucune couverture côté backend** : pas de JaCoCo | `back/build.gradle` | Couverture Java = 0 mesuré, alors que c'est la stack la plus fragile de l'équipe |
| C8 | **Aucun lint** (ni ESLint, ni Checkstyle, ni ShellCheck) | absent du dépôt | La demande n°1 des Dev (« éviter les mauvaises pratiques ») n'est pas outillée |
| C9 | **Aucune étape de déploiement** | `.gitlab-ci.yml` | Déploiement 100 % manuel côté Ops |
| C10 | **Ordre des étapes non argumenté** et partiellement redondant : `build-front` refait le `npm ci` déjà fait par `test-front` | `.gitlab-ci.yml` | ~2× le temps d'installation des dépendances |

### 1.4 Le code applicatif — dette technique visible

| # | Constat | Preuve | Impact |
|---|---|---|---|
| A1 | **Divergence Dev/Ops sur la base de données** : les Dev utilisent **HyperSQL** (en mémoire), les Ops déclarent **PostgreSQL** comme SGBD | Sondage Dev « HyperSQL » vs sondage Ops « PostgreSQL » ; `build.gradle` l. 25 `runtimeOnly 'org.hsqldb:hsqldb'` | **Écart dev/prod majeur** : aucune donnée n'est persistée, et le SGBD de production n'est jamais testé |
| A2 | **Version figée `0.0.1-SNAPSHOT`** en dur | `build.gradle` l. 9 ; `Dockerfile` l. 34 | Aucun versionnement sémantique, aucune traçabilité de release, chemin du JAR codé en dur dans le Dockerfile |
| A3 | **Dépendance déclarée deux fois** (`spring-boot-starter-data-jpa`) | `build.gradle` l. 20-21 | Symptôme de l'inexpérience Gradle déclarée ; qu'un lint aurait relevé |
| A4 | **API exposée sans authentification** : `spring-boot-starter-data-rest` publie les repositories JPA en HTTP, sans `spring-boot-starter-security` | `build.gradle` l. 19-27 | Données CRM en lecture/écriture pour quiconque atteint l'API (OWASP A01) |
| A5 | **`EXPOSE 4200` dans l'étage `back`** alors que Spring Boot écoute sur **8080** | `Dockerfile` l. 40 vs `README.md` l. 140 | Métadonnée fausse ; casse toute orchestration qui s'y fie (K8s, compose) |
| A6 | **Étage `standalone` copie deux systèmes de fichiers entiers** (`COPY --from=front / /`) | `Dockerfile` l. 46-47 | Image obèse, surface d'attaque maximale, contenu non maîtrisé |
| A7 | **Conteneurs exécutés en `root`** (aucune directive `USER`) | `Dockerfile` (4 étages) | Élévation de privilèges en cas d'évasion (OWASP A05) |
| A8 | **Images de base non épinglées** dans le Dockerfile (`node`, `gradle:jdk17`) et paquets installés sans version (`apk add caddy`, `apk add openjdk21-jre-headless`) | `Dockerfile` l. 1, 10, 23, 36 | Non-reproductibilité ; **c'est le vecteur direct des CVE subies** |
| A9 | **Incohérence de JDK** : compilation en **17**, exécution en **21** | `build.gradle` l. 12 vs `Dockerfile` l. 36 | Écart build/runtime non maîtrisé |
| A10 | **Aucun `HEALTHCHECK`**, aucune sonde de vivacité | `Dockerfile` | Impossible pour un orchestrateur de savoir si l'app est saine |

---

## 2. SWOT du processus CI d'Orion

### 🟢 Forces (interne, positif)

- **F1 — Un socle CI existe déjà** : le réflexe « tests automatisés à chaque itération » est acquis. On
  part d'un pipeline fonctionnel, pas de zéro. La bascule sera une **montée en puissance progressive**,
  pas une rupture.
- **F2 — Application déjà conteneurisée** et pensée multi-composants : un `Dockerfile` multi-stage
  produit 3 artefacts (front, back, standalone). Le passage à Kubernetes est donc à portée.
- **F3 — Docker maîtrisé des deux côtés** (« Bon » chez Dev **et** chez Ops) : c'est le **langage commun**
  des deux équipes, la fondation naturelle de la démarche DevOps.
- **F4 — Culture sécurité déjà présente côté Ops** : Trivy est **déjà utilisé**. Il ne s'agit pas
  d'introduire un outil inconnu, mais de le **déplacer en amont** (shift-left).
- **F5 — Excellence Bash/Ansible côté Ops** (Bash « Très bon », BashUnit et TestInfra « Bon ») :
  les scripts d'automatisation exigés seront écrits **dans la langue maternelle de l'équipe**, donc
  maintenus par elle. Idem pour les tests `bash_unit`.
- **F6 — Frontend solide** : Angular/TypeScript/Karma « Bon », `karma-coverage` déjà installé —
  la couverture front est à un paramètre près.
- **F7 — Timing idéal** : l'application n'est **pas encore en production** (2ᵉ sprint). Toutes les
  contraintes peuvent être posées **avant** que la dette ne se solidifie, sans dette de migration ni
  risque de régression sur un service vivant. *C'est la plus grande force du projet.*
- **F8 — Demande émanant du terrain** : les deux équipes réclament elles-mêmes analyse statique et
  scan d'images. **L'adhésion au changement est acquise d'avance** — le facteur d'échec n°1 d'une
  transformation DevOps est neutralisé.

### 🔴 Faiblesses (interne, négatif)

- **f1 — Sécurité totalement absente de la CI** (C1) : ni SAST, ni scan de dépendances, ni scan d'image.
  **Une CVE a déjà retardé un déploiement.** C'est la faiblesse n°1, factuellement démontrée.
- **f2 — L'artefact livré n'est pas produit par la CI** (C2) : les images Docker, seul livrable réel,
  sont construites à la main sur les postes. La CI teste un code, mais **ne certifie pas ce qui est livré**.
- **f3 — Déploiement 100 % manuel** (C9) : `docker run` à la main par 2 personnes. Non reproductible,
  non traçable, non délégable, non rejouable.
- **f4 — Aucune traçabilité de version** (A2, C3) : `0.0.1-SNAPSHOT` figé, aucun tag, aucun artefact
  conservé. **Question sans réponse aujourd'hui : « quel commit tourne sur la démo ? »**
- **f5 — Aucune reproductibilité** (C4, A8) : toutes les images de base flottent. Deux builds du même
  commit peuvent produire deux résultats différents — et l'un peut être vulnérable.
- **f6 — Écart dev/prod sur la base de données** (A1) : HSQLDB en mémoire côté Dev vs PostgreSQL côté
  Ops. **Le SGBD cible n'est jamais exercé**, et la compétence PostgreSQL est le seul point « Moyen » de
  l'équipe Ops.
- **f7 — Qualité de code non mesurée** (C6, C7, C8) : aucun lint, aucune couverture exploitable.
  Sur la stack où l'équipe est **Débutante** (Java/Spring/JUnit), **rien ne l'alerte**.
- **f8 — Aucun back-up, aucun rollback** : rien dans le processus ne permet de revenir en arrière ni de
  restaurer un état. Le jour où l'app passe en production, l'incident est ingérable.
- **f9 — Communication Dev↔Ops par e-mail et oral** : le processus repose sur des « retours à
  l'envoyeur » informels. Aucun historique, aucune métrique, silo organisationnel.
- **f10 — Charge Ops structurellement intenable** : **2 personnes** pour tout le déploiement manuel.
  Facteur bus = 1 sur plusieurs opérations clés.
- **f11 — Sous-dimensionnement backend de l'équipe Dev** : Java/Spring/Gradle/JUnit tous **Débutants**,
  alors que le backend porte les données CRM. La dette technique (A3, A4) en est la conséquence directe.

### 🔵 Opportunités (externe, positif)

- **O1 — Registre d'images géré (GHCR)** : répond exactement à la demande Ops (« ne plus dépendre de
  Docker Hub »), inclus dans la plateforme, avec authentification native de la CI et rétention gérée.
  **Coût marginal nul** sur dépôt public, et supprime au passage la limite de pull anonyme Docker Hub.
- **O2 — SonarQube / SonarCloud** : répond exactement à la demande Dev. Détecte automatiquement les
  mauvaises pratiques Java qu'une équipe Débutante ne peut pas voir, et fournit les **security hotspots**.
  Gratuit sur dépôt public.
- **O3 — Trivy en CI** : l'outil est **déjà connu et adopté** par l'Ops. Le déplacer dans le pipeline
  supprime le cycle « retour à l'envoyeur » sans aucun coût d'apprentissage. **Gain immédiat, friction nulle.**
- **O4 — Kubernetes + Helm** : rend le déploiement déclaratif, reproductible et surtout **réversible**
  (`helm rollback`), transformant les 2 Ops en pilotes plutôt qu'en exécutants.
- **O5 — Terraform + Ansible** : Ansible est déjà « Bon » chez l'Ops. L'IaC capitalise sur un acquis.
- **O6 — Stack ELK** : donne enfin une **observabilité** à une équipe qui n'a aujourd'hui aucune vue
  sur l'exécution de l'application.
- **O7 — Métriques DORA** : fournissent un langage **chiffré et non technique** pour dialoguer avec
  Maria et la direction — et pour prouver le gain de la démarche.
- **O8 — Templates CI standards & actions réutilisables** : réduisent le coût de mise en œuvre et
  l'inexpérience de l'équipe sur la CI.
- **O9 — Fenêtre pré-production** : construire la chaîne **avant** le premier passage en production est
  un privilège rare — aucun risque de régression sur un service en exploitation.

### 🟠 Menaces (externe, négatif)

- **M1 — Le prochain incident CVE bloquera une mise en production**, pas seulement une démo. La menace
  s'est **déjà réalisée une fois** dans un contexte sans enjeu ; elle se reproduira avec enjeu.
- **M2 — Fuite de données via l'API non authentifiée** (A4) : dès l'exposition réseau, les données CRM
  (personnes, organisations — **données à caractère personnel, donc RGPD**) sont accessibles à tous.
- **M3 — Fuite de secrets** : sans gestion outillée des secrets, les credentials du futur registre
  finiront versionnés en clair. Risque explicitement pointé par le guide mentor.
- **M4 — Dérive silencieuse des images de base** (A8) : une image `node` ou `alpine` non épinglée
  intègre des CVE **sans aucun changement de code** — donc sans aucun signal.
- **M5 — Perte de données garantie** : HSQLDB en mémoire (A1) + aucun back-up (f8). Le premier
  redémarrage en production efface tout.
- **M6 — Dépendance à Docker Hub** : *rate limits* sur les pulls anonymes, et dépendance à un tiers
  pour la chaîne de livraison (menace identifiée par l'Ops elle-même).
- **M7 — Surcharge de l'équipe Ops (2 personnes)** : le manuel ne passera pas à l'échelle au premier
  incident nocturne ni au premier départ.
- **M8 — Perte de la mémoire projet** : sans traçabilité des versions (f4), on ne saura ni ce qui
  tourne, ni ce qu'il faut restaurer, ni ce qui a introduit une régression.

---

## 3. Goulots d'étranglement identifiés

| # | Goulot | Coût actuel | Levée par |
|---|---|---|---|
| **G1** | **Contrôle de sécurité placé en aval** (Ops, manuel, après transmission) | Cycle « retour à l'envoyeur » complet : retard déjà constaté d'un déploiement | Trivy + `npm audit`/`gradle dependencyCheck` **dans la CI** (shift-left) |
| **G2** | **Construction manuelle des 3 images** | Temps développeur à chaque livraison + risque d'erreur humaine + non-reproductibilité | Build + push GHCR automatisés par la CI |
| **G3** | **Déploiement manuel via `docker run`** | 2 personnes mobilisées, non rejouable, non traçable | Helm + Kubernetes déclaratif |
| **G4** | **Transmission de version par e-mail** | Latence humaine, aucun historique | Tags sémantiques + `semantic-release` + registre |
| **G5** | **`npm ci` exécuté deux fois** (test puis build) sans cache | Durée de pipeline ~doublée sur l'étape la plus lente | Cache de dépendances + réutilisation d'artefacts |
| **G6** | **Compétence backend Débutante non outillée** | Dette technique introduite sans détection (A3, A4) | SonarQube en quality gate bloquante |

---

## 4. Lacunes de sécurité — synthèse

| Réf. | Lacune | Gravité | OWASP Top 10 (2021) |
|---|---|---|---|
| **S1** | Aucune analyse de sécurité dans la CI (SAST/SCA/image) | **Critique** | A06 — Composants vulnérables et obsolètes |
| **S2** | API REST exposée sans authentification ni autorisation | **Critique** | A01 — Contrôle d'accès défaillant |
| **S3** | Images de base et paquets non épinglés → CVE non maîtrisées | **Élevée** | A06 / A08 — Intégrité des données et logiciels |
| **S4** | Conteneurs exécutés en `root` | **Élevée** | A05 — Mauvaise configuration de sécurité |
| **S5** | Aucune gestion outillée des secrets (registre, BDD) | **Élevée** | A07 — Défaillances d'identification/authentification |
| **S6** | Étage `standalone` embarquant des systèmes de fichiers entiers | **Moyenne** | A05 — Surface d'attaque non maîtrisée |
| **S7** | Aucun journal centralisé, aucune alerte, aucune traçabilité d'accès | **Moyenne** | A09 — Carences des systèmes de journalisation et de surveillance |
| **S8** | Aucune sauvegarde ni procédure de restauration | **Moyenne** | *(hors OWASP applicatif — risque de continuité d'activité)* |
| **S9** | Absence de traçabilité des versions déployées | **Moyenne** | A08 — Intégrité des données et logiciels |

---

## 5. Conclusion de l'audit

Le processus CI d'Orion n'est pas défaillant : il est **incomplet et arrêté trop tôt**. Il valide le
code, mais **ne certifie ni ne livre l'artefact réel** — l'image Docker —, qui reste construite,
contrôlée et déployée à la main par deux personnes.

Trois constats structurent les recommandations qui suivent :

1. **Le point de rupture est identifié et déjà éprouvé** : la sécurité intervient en aval, à la main,
   par la mauvaise équipe. L'incident CVE l'a démontré sans ambiguïté. → **Priorité absolue au
   shift-left sécurité** (SonarQube + Trivy + scan de dépendances dans le pipeline).
2. **Les compétences de chaque équipe dictent les outils** : Bash/Ansible pour l'Ops (Très bon/Bon),
   analyse statique pour compenser le niveau Débutant des Dev en Java. Une recommandation qui ignore
   cette cartographie ne sera pas adoptée.
3. **La fenêtre est optimale** : l'application n'est pas en production. Les garde-fous peuvent être
   posés avant que la dette ne devienne irréversible et sans risque de régression.

➡️ **Suite** : `docs/02-veille-recommandations.md` (solutions comparées, coût/bénéfice), puis
`docs/03-normalisation-plan-ci.md` (structure cible du pipeline et ordre d'exécution argumenté).
