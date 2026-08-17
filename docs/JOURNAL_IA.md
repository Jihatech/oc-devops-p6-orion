# Journal de l'IA et de la méthodologie

> **Objet** : tracer honnêtement l'usage de l'IA générative, les décisions prises, leurs raisons, et
> **ce qui a été vérifié à la main**. Ce journal répond aux questions de soutenance :
> *« Comment avez-vous fait pour [livrable] ? »*, *« Quelle a été la méthodologie suivie ? »*,
> *« Quelles ont été les différentes étapes ? »*
>
> **Position assumée** : l'IA a été utilisée comme **assistant de rédaction et d'implémentation**,
> jamais comme source de vérité. Toute affirmation factuelle de ce projet est **ancrée sur une source
> vérifiable** — les deux sondages Orion, ou le code fourni, cité fichier et ligne à l'appui.

---

## Méthodologie générale

Le projet est mené en **6 phases avec point de contrôle** entre chacune, plutôt qu'en une seule passe.
Raison : c'est un projet de synthèse évalué en soutenance, et une erreur d'orientation en phase 1 se
propagerait à tout le reste. Chaque phase est validée avant d'engager la suivante.

**Principe de travail appliqué à chaque livrable** :

1. Lire la source primaire (sondage, code, fiche d'évaluation) **avant** de rédiger quoi que ce soit.
2. Établir les constats **avec leur preuve** (fichier + ligne, ou citation du sondage).
3. Décider et **argumenter**, en documentant aussi ce qui est **écarté** et pourquoi.
4. Vérifier par exécution réelle (commande, pipeline, test) chaque fois que c'est possible.

---

## Phase 1 — Audit et conception

**Période** : 16/08/2026
**Livrables** : `01-audit-swot.md`, `02-veille-recommandations.md`, `03-normalisation-plan-ci.md`

### Démarche suivie

| # | Étape | Détail |
|---|---|---|
| 1 | **Récupération des sources primaires** | Téléchargement des deux sondages Orion (Dev + Ops) depuis les URL officielles OC ; extraction du texte (les PDF ne sont pas en texte sélectionnable propre) ; dépôt dans `docs/contexte/`. |
| 2 | **Analyse directe du code fourni** | Clone du dépôt applicatif OC, puis **lecture ligne à ligne** de `.gitlab-ci.yml` (34 l.), `Dockerfile` (54 l.), `back/build.gradle`, `front/package.json`, `front/karma.conf.js`, `README.md`. |
| 3 | **Croisement sondages × code** | Chaque constat de l'audit est rattaché soit à une déclaration d'équipe, soit à une ligne de code. C'est ce croisement qui produit les constats les plus forts (voir « Découvertes » ci-dessous). |
| 4 | **Rédaction du SWOT** | Structuré en 4 quadrants, puis goulots (G1–G6) et lacunes de sécurité (S1–S9) mappées sur l'OWASP Top 10 2021. |
| 5 | **Veille comparative** | 8 familles d'outils, évaluées sur 5 critères (compétences, coût, effort, gain, risque). Une section §9 documente les **9 solutions écartées** avec justification. |
| 6 | **Plan de normalisation** | 5 principes directeurs, ordre d'exécution argumenté étape par étape, portes de qualité chiffrées, matrice de déclenchement, schémas Mermaid. |

### Découvertes issues du croisement (non déductibles d'une seule source)

Ce sont les constats dont je suis le plus certain de pouvoir défendre l'origine en soutenance, car
aucun ne provient d'un « savoir général » :

1. **Divergence Dev/Ops sur la base de données** (A1) — le sondage Dev déclare **HyperSQL**, le sondage
   Ops déclare **PostgreSQL**. Confirmé par `back/build.gradle` l. 25 (`runtimeOnly 'org.hsqldb:hsqldb'`).
   Les deux équipes ne parlent pas du même SGBD, et personne ne semble l'avoir relevé.
2. **Les deux équipes demandent d'elles-mêmes les outils du projet** — les Dev demandent « des outils
   d'analyse statique » (= SonarQube), les Ops demandent « un dépôt d'images interne » (= GHCR) et
   « des outils d'analyse de sécurité des images en amont » (= Trivy en CI). Les recommandations ne
   sont donc **pas imposées** : elles répondent à une demande interne existante.
3. **L'incident CVE du sondage Dev et l'irritant « retour à l'envoyeur » du sondage Ops décrivent le
   même événement**, vu des deux côtés. C'est le fil conducteur de tout l'audit : la sécurité est
   contrôlée en aval, à la main, par la mauvaise équipe.
4. **`EXPOSE 4200` dans l'étage `back`** (`Dockerfile` l. 40) alors que Spring Boot écoute sur 8080
   (`README.md` l. 140). Erreur silencieuse aujourd'hui (aucun orchestrateur ne s'en sert), bloquante
   demain sous Kubernetes.
5. **`karma-coverage` est installé et configuré mais jamais exploité** (`karma.conf.js` l. 30-34,
   reporters `html` + `text-summary`, pas de `lcov`). La couverture est à un paramètre près — un
   constat impossible à formuler sans avoir ouvert le fichier.
6. **Dépendance déclarée deux fois** dans `build.gradle` (l. 20-21) — symptôme concret du niveau
   « Gradle : Débutant » déclaré par l'équipe, et argument direct en faveur du lint.

### Décisions prises en phase 1

| Décision | Alternative écartée | Raison |
|---|---|---|
| **GitHub Actions** | GitLab CI | Pas de quota de minutes sur dépôt public ; GHCR intégré ; validé par le mentor le 31/07/2026. Une **table de correspondance GitHub ↔ GitLab** est fournie (`02` §10) pour démontrer la portabilité. |
| **SonarCloud** (moteur SonarQube) | Serveur Community en service container | Le serveur éphémère **perd l'historique** à chaque exécution — or la mesure de tendance est l'objectif même du rapport de performance. |
| **Trivy en CI** | Grype, Snyk, Docker Scout | **Déjà utilisé par l'Ops** : coût d'apprentissage nul, adoption acquise. |
| **GHCR** | Harbor auto-hébergé | Harbor répond à la lettre (registre interne) mais ajoute un serveur à administrer à **2 Ops déjà en surcharge**. |
| **Minikube** | EKS/AKS managé | ~70 €/mois sans bénéfice pour une app hors production. Contrepartie assumée : un plan de migration cloud **concret et chiffré** (`09`). |
| **Trunk-based** | GitFlow | Équipe de 4, livraisons fréquentes ; GitFlow dégraderait le *lead time*, que le projet vise justement à améliorer. |
| **Couverture à 60 %**, pas 80 % | Seuil élevé | Équipe **Débutante en JUnit**, 2ᵉ sprint. Un seuil inatteignable est désactivé à la première urgence. Seuil appliqué au **code nouveau** : la dette cesse de croître sans exiger de reprise rétroactive. |
| **Trivy `--ignore-unfixed`** | Blocage sur toute CVE | Bloquer sur une CVE **sans correctif disponible** revient à bloquer sur un problème insoluble par l'équipe — seule issue : désactiver le contrôle. Les non-corrigibles sont **rapportées et suivies**. |
| **Ne pas migrer vers PostgreSQL** | Corriger A1 | Modifierait le **code applicatif fourni** — hors périmètre (industrialiser, pas réécrire). Documenté comme **recommandation n°1** d'amélioration continue. |
| **Ne pas ajouter Spring Security** | Corriger S2/A4 | Même raison. La faille est **signalée comme critique** au rapport ; la CI la **détecte** (Sonar), elle ne la corrige pas. |

### Usage de l'IA en phase 1

| Usage | Nature |
|---|---|
| Extraction du texte des PDF de sondage | Script Python (`pypdf`) — mécanique |
| Structuration et rédaction des 3 documents | **Assistée par IA**, à partir des constats que j'ai établis |
| Mise en forme des schémas Mermaid | Assistée |
| **Constats techniques (C1–C10, A1–A10)** | **Issus de la lecture du code — chacun vérifiable, fichier et ligne cités** |
| **Décisions d'architecture et arbitrages** | **Miennes** — motifs et alternatives écartées documentés ci-dessus |

**Vérifications manuelles effectuées** : contrôle des versions de la chaîne d'outils locale (git 2.54,
Docker 28.5.1, Terraform 1.15.6, Node 25.2.1, Python 3.11.15, gh 2.96) ; lecture intégrale des fichiers
cités ; vérification que le lanceur `ChromeHeadlessNoSandbox` référencé par la CI existe bien dans
`karma.conf.js` (il existe — donc ce job n'est pas cassé, contrairement à une hypothèse initiale que
j'ai dû abandonner après vérification).

### Points à confirmer avant la phase 2

- Docker Desktop n'était pas démarré au moment de la phase 1 (indispensable aux phases 4 et 5).
- Le jeton `gh` porte les portées `repo` et `workflow` ; la publication GHCR passera par le
  `GITHUB_TOKEN` du pipeline, sans jeton personnel.

---

## Phase 2 — Pipeline CI et scripts d'automatisation

*(à compléter)*

## Phase 3 — DevSecOps

*(à compléter)*

## Phase 4 — Conteneurisation, orchestration, release

*(à compléter)*

## Phase 5 — IaC, monitoring, DORA

*(à compléter)*

## Phase 6 — Consolidation des livrables

*(à compléter)*
