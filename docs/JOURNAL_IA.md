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

**Période** : 17/08/2026
**Livrables** : `.github/workflows/ci.yml`, `scripts/` (6 fichiers), outillage qualité front/back

### Démarche suivie

| # | Étape | Détail |
|---|---|---|
| 1 | **Vérifier avant d'écrire** | Build Gradle exécuté en local **avant** toute écriture de pipeline : succès, JAR de 47 Mo, 2 classes de test. On ne construit pas une CI sur un build dont on ignore s'il passe. |
| 2 | **Bibliothèque partagée d'abord** | `scripts/lib/commun.sh` écrite en premier, en isolant les fonctions **pures** (sans effet de bord) — ce sont elles qui seront testables unitairement. |
| 3 | **Scripts** | 5 scripts, chacun avec l'en-tête exigé : BUT, FONCTIONNEMENT, PARAMÈTRES, CONDITIONS D'EXÉCUTION, exemples et codes de sortie documentés. |
| 4 | **Tests avant pipeline** | 27 tests bash_unit écrits et exécutés en local, ShellCheck 0.11.0 passé en `--severity=style`, avant le premier push. |
| 5 | **Outillage qualité** | ESLint (front), JaCoCo (back), LCOV et JUnit XML — les formats que SonarQube consommera en phase 3. |
| 6 | **Pipeline** | 8 jobs, versions épinglées, permissions minimales, appel des scripts plutôt que duplication de leur logique. |
| 7 | **Itération jusqu'au vert** | 4 exécutions successives, chaque échec corrigé à la racine et transformé en garde-fou. |

### Décision de conception structurante

**Le pipeline appelle les scripts ; il ne réimplémente pas leur logique.** `install-deps.sh` et
`run-tests.sh` sont invoqués tels quels par les jobs. Conséquences :

- un développeur reproduit **exactement** le comportement de la CI sur son poste ;
- une correction apportée à un script bénéficie simultanément aux deux environnements ;
- l'exigence « scripts d'automatisation » n'est pas satisfaite par des scripts décoratifs posés à côté
  d'un pipeline qui ferait le vrai travail — ils **sont** le pipeline.

### Les 4 échecs de pipeline et ce qu'ils ont produit

Ces incidents sont conservés ici intégralement : ils sont la meilleure réponse aux questions
« quels défis avez-vous rencontrés ? » et « quelle méthodologie ? ».

| # | Échec | Cause réelle | Correction — et garde-fou ajouté |
|---|---|---|---|
| 1 | `lint-scripts` rouge (SC2015) | `A && B \|\| C` dans `deploy-build.sh` : ce n'est pas un if-then-else, C peut s'exécuter alors que A est vrai | Bloc `if` explicite. **Et surtout** : le runner embarquait ShellCheck **0.9.0**, mon poste **0.11.0** — le défaut était invisible en local. J'ai **épinglé la version dans la CI**, ce qui aligne poste et runner. C'est l'application à moi-même du principe P5 que je reprochais au pipeline d'origine. |
| 2 | `build-back` en **exit 126** | `app/back/gradlew` versionné en `100644` : le bit exécutable a été perdu à l'intégration sous Windows, qui ne le porte pas | `git update-index --chmod=+x`. **Garde-fou** : le job de lint vérifie désormais le bit exécutable de tous les scripts **et de `gradlew`**, avec le message de correction exact. L'incident ne peut plus se reproduire silencieusement. |
| 3 | `test-scripts` rouge | `bash_unit --version` n'existe pas : l'option est `-v` | Option corrigée. Rappel utile : ce que je crois d'un outil doit être vérifié contre l'outil, pas contre ma mémoire. |
| 4 | `test-front` rouge **alors que les 8 tests passaient** | Mon agrégateur JUnit lisait l'attribut `skipped`, que Gradle émet mais que karma-junit-reporter **omet**. La chaîne vide injectée en arithmétique donnait « operand expected » | Extraction isolée dans la fonction **pure** `attribut_xml` (retourne 0 sur attribut absent), **couverte par 4 nouveaux tests bash_unit**. Le défaut ne peut plus revenir sans faire échouer les tests. |

**Ce que ces incidents montrent** : trois des quatre étaient **invisibles sur le poste de
développement** et n'ont été révélés que par la CI. C'est précisément l'argument en faveur de
l'automatisation chez Orion, où tout est aujourd'hui exécuté à la main sur des postes.

### Découverte : la couverture réelle du projet

Première mesure jamais réalisée sur ce code (l'audit avait relevé qu'aucune couverture n'était
collectée) :

| Composant | Couverture | Lecture |
|---|---|---|
| Backend (instructions) | **65,9 %** | Au-dessus du seuil de 60 % retenu |
| Frontend (lignes) | **30,8 %** | En dessous — 33,1 % d'instructions, **9,5 % de branches** |

Le frontend est donc le point faible réel, alors que l'équipe se déclare « Bonne » en Angular et
Karma — et le backend, où elle se dit Débutante, est mieux couvert. **La perception de l'équipe est
inverse de la mesure.** C'est exactement ce qu'un système de mesure sert à révéler, et cela alimentera
le rapport de performance.

### Arbitrage assumé : ESLint ne bloque pas sur la dette antérieure

ESLint a remonté **13 défauts dans le code fourni** dès sa première exécution — ce qui valide la
demande de l'équipe Dev. Décision : n'en corriger qu'un (import `Router` mort, risque nul) et
**basculer en avertissement** les 12 autres (accessibilité des libellés, `no-explicit-any`).

Motif : ce sont des défauts **antérieurs au projet**, dont la correction relève du développement
applicatif, hors périmètre. Les rendre bloquants aurait imposé de modifier le code fourni ou de
désactiver la règle. L'avertissement les garde **visibles et comptés** sans bloquer. C'est la même
logique que le seuil de couverture à 60 % (docs/03, §5.1) : **un garde-fou inatteignable est un
garde-fou qui sera désactivé.**

### Résultat mesuré

| Indicateur | Valeur |
|---|---|
| Exécution verte | [31994739494](https://github.com/Jihatech/oc-devops-p6-orion/actions/runs/31994739494) — 8/8 jobs |
| Durée totale | **1 min 45 s** (cible du plan : moins de 12 min) |
| Tests exécutés | **10** (8 front + 2 back), 100 % de réussite |
| Tests unitaires de scripts | **27** bash_unit |
| ShellCheck | 0 défaut en `--severity=style` |
| ESLint | 0 erreur, 12 avertissements suivis |

### Usage de l'IA en phase 2

| Usage | Nature |
|---|---|
| Rédaction des scripts et du workflow | **Assistée par IA**, sur une conception que j'ai arrêtée (découpage, fonctions pures, parité poste/CI) |
| Diagnostic des 4 échecs | **Mien** — lecture des journaux d'exécution réels, puis correction à la racine |
| Vérification | **Exécution réelle systématique** : bash_unit, ShellCheck, ESLint, Gradle, et 4 exécutions de pipeline |

**Incident méthodologique à signaler** : j'ai d'abord cru ShellCheck défaillant parce qu'il ne
signalait rien sur `foo=1 ; echo $foo`. C'était **mon test de contrôle qui était faux** — ShellCheck
ne déclenche pas SC2086 quand la valeur assignée est un littéral sans espace ni glob. Vérifié avec un
cas indiscutable (`cd $1`), l'outil fonctionnait parfaitement. Leçon retenue et appliquée depuis :
**un test de contrôle doit lui-même être validé avant d'accuser l'outil.**

## Phase 3 — DevSecOps

**Période** : 18/08/2026
**Livrables** : étape ④ du pipeline (2 jobs), `scan-securite.sh`, `sonar-analyse.sh`,
`sonar-report.py`, `.trivyignore.yaml`, `docs/04-plan-tests.md`, `docs/05-plan-securite.md`,
preuves dans `docs/captures/sonarqube/`

### Décision n°1 — SonarQube : serveur en conteneur plutôt que SonarCloud

La mission laisse le choix, à condition de le documenter. Les deux options ont été comparées sur
cinq critères :

| Critère | Serveur en conteneur *(retenu)* | SonarCloud |
|---|---|---|
| Dépendance externe | **Aucune** | Compte, organisation, projet à créer |
| Secret à gérer | **Aucun** — jeton généré à l'exécution | `SONAR_TOKEN` à déposer et faire tourner |
| Reproductibilité par un tiers | **Totale** — l'évaluateur relance le pipeline sans rien configurer | Impossible sans accès au compte |
| Historique de tendance | ⚠️ Perdu avec le conteneur | Natif |
| Décoration des Pull Requests | Non | Oui |

**Motif du choix** : la reproductibilité sans dépendance ni secret. Une chaîne de sécurité ne doit
pas elle-même reposer sur un compte externe dont l'évaluateur n'a pas la clé.

> ⚠️ **Révision assumée d'une décision de phase 1.** Le document `02-veille-recommandations.md`
> recommandait SonarCloud, précisément parce qu'il conserve l'historique. Ce point était juste, et
> c'était le principal argument. Il est traité autrement plutôt qu'abandonné : `sonar-report.py`
> interroge l'API **avant** la destruction du serveur et écrit une ligne datée, rattachée à un
> commit, dans un `historique.csv` **versionné**. La tendance est donc conservée — et sous une forme
> plus solide qu'une capture d'écran, puisqu'elle est comparable automatiquement et qu'une
> modification apparaîtrait dans l'historique Git.

### Décision n°2 — Acceptations de risque nommées plutôt que seuil abaissé

Trivy a remonté **12 CVE HIGH** sur `@angular/core`, `@angular/common` et `@angular/compiler` en
17.3.8. Pour **chacune**, la version corrigée la plus basse est **Angular 19.2** : aucun correctif
n'existe en branche 17. Les traiter suppose une montée de deux versions majeures — une migration
applicative, hors périmètre d'une mission d'industrialisation.

Deux réponses possibles :

| Option | Effet | Retenue |
|---|---|---|
| Abaisser le seuil bloquant de HIGH à CRITICAL | Rend le pipeline **aveugle à toute nouvelle vulnérabilité HIGH**, y compris corrigeable | ❌ |
| Accepter **nommément** les 12 CVE dans `.trivyignore.yaml` | Le seuil reste à HIGH ; **toute nouvelle vulnérabilité HIGH bloque** | ✅ |

Chaque acceptation porte une justification et une **date d'expiration** (30/11/2026). Aucune
acceptation permanente n'est admise. C'est la différence entre *gérer* un risque et le *masquer*.

### Décision n°3 — La porte npm audit porte sur les dépendances de production

Une vulnérabilité d'un outil de construction (Angular CLI, Karma) n'est **jamais servie au
navigateur**. Bloquer une livraison applicative sur un risque de chaîne de build est une erreur de
catégorie. Le gate porte donc sur `npm audit --omit=dev` ; le reste est rapporté dans un second
fichier et suivi.

### Vulnérabilités effectivement corrigées

**Dépendances** — `npm audit fix`, sans montée de version majeure :

| | Avant | Après |
|---|---|---|
| Total | 88 | **53** (−40 %) |
| Critiques (toutes) | 3 | **1** |
| **Critiques (production)** | — | **0** |

Corrigées : `shell-quote` (déni de service à complexité quadratique) et `websocket-driver`
(contournement de limite de ressources). Restante : `tar` via `@angular/cli`, qui exige une montée
majeure et ne concerne que la chaîne de build (risque R9).

**Code** — les 4 défauts SonarQube, du plus grave au moins grave :

| Règle | Sévérité | Nature |
|---|---|---|
| `java:S1186` | CRITICAL | Test `contextLoads()` **vide** — passait toujours sans rien vérifier |
| `typescript:S7059` | CRITICAL | Appel asynchrone **dans un constructeur** |
| `Web:S5256` | MAJOR | Tableau sans en-têtes `<th>` |
| `Web:MouseEvent…` | MINOR | Clic porté par un `<span>`, inaccessible au clavier |

Résultat mesuré : **bugs 2 → 0**, code smells 35 → 33, **note de fiabilité C → A**, avertissements
ESLint 12 → 10. Preuves complètes dans `docs/captures/sonarqube/`.

### Les 3 échecs de pipeline de la phase, et ce qu'ils ont produit

| # | Échec | Cause réelle | Correction — et garde-fou |
|---|---|---|---|
| 1 | Job SonarQube rouge **alors que l'analyse avait réussi** (26 fichiers, rapport transmis) | Mon script dépendait entièrement de `.scannerwork/report-task.txt`, écrit par le **conteneur** du scanner : ni sa présence ni ses droits ne sont garantis | Clé de projet lue dans `sonar-project.properties` et transmise explicitement ; **repli** par interrogation de la file de traitement du projet si l'identifiant de tâche manque |
| 2 | Job de lint rouge sur `npm ci` | J'avais appliqué `npm audit fix` avec `--legacy-peer-deps`, produisant un verrou que `npm ci` **refuse** d'installer | Verrou régénéré sans le drapeau, et **`npm ci` vérifié en local avant envoi** — la vérification qui manquait |
| 3 | Job de sécurité rouge **au moment précis où il ne trouvait rien** | Sous `set -o pipefail`, un `grep` sans correspondance renvoie 1 : le comptage « 0 vulnérabilité » faisait échouer le script via `set -e` | Comptage isolé dans `compter_occurrences()`, **couverte par 4 tests bash_unit** dont un qui vérifie explicitement la survie sous `set -euo pipefail` |

**Le 3ᵉ mérite d'être souligné** : le résultat recherché — *aucune vulnérabilité* — provoquait
l'échec du contrôle. ShellCheck ne détecte pas cette classe d'erreur ; **seule l'exécution la
révèle**. C'est un argument concret en faveur de l'automatisation, et la raison pour laquelle je
teste les scripts d'exploitation au même titre que le code applicatif.

### Constat honnête : 0 vulnérabilité et 0 security hotspot

L'analyse n'en a détecté aucun. Ce n'est **pas** un défaut de configuration : les classes Java
compilées étaient bien fournies à l'analyseur (sans elles, il n'aurait rien pu détecter — c'est
d'ailleurs pourquoi le job compile avant d'analyser).

L'explication tient à l'application : un CRUD sans authentification, sans cryptographie, sans appels
sortants. Et surtout, **la faille réelle qu'elle porte — l'API REST sans authentification — est une
absence de contrôle**, que l'analyse statique ne sait pas détecter : SonarQube signale du code
dangereux, pas du code manquant. C'est documenté comme risque résiduel R1, le plus grave du projet.

Je préfère le dire ainsi plutôt que de laisser croire à une couverture que l'outil n'apporte pas.

### Résultat mesuré

| Indicateur | Valeur |
|---|---|
| Exécution verte | [32091061723](https://github.com/Jihatech/oc-devops-p6-orion/actions/runs/32091061723) — **10/10 jobs** |
| Contrôles de sécurité automatisés | **5** (SAST, dépendances ×2, secrets, configurations) — contre **0** avant |
| Quality gate | ✅ OK |
| Tests unitaires de scripts | **31** bash_unit (+4 de régression) |
| Durée de l'analyse SonarQube | 2 min 21 s |

### Usage de l'IA en phase 3

| Usage | Nature |
|---|---|
| Rédaction des scripts, du workflow et des deux plans | **Assistée par IA**, sur des décisions que j'ai arrêtées et documentées ci-dessus |
| Diagnostic des 3 échecs | **Mien** — lecture des journaux et des artefacts JSON réels |
| Analyse des 12 CVE et de leurs versions correctives | **Mienne** — extraction depuis le rapport Trivy, vérification que la branche 17 n'a aucun correctif |
| Vérification | **Exécution réelle** : 5 exécutions de pipeline, artefacts téléchargés et inspectés, `npm ci` et tests rejoués en local |

**Point de méthode** : après l'incident n°2 (verrou npm cassé), j'ai systématisé la vérification
locale de `npm ci` **avant** tout envoi. Corriger un défaut ne suffit pas ; il faut corriger ce qui
a permis de ne pas le voir.

## Phase 4 — Conteneurisation, orchestration, release

**Période** : 18/08/2026
**Livrables** : Dockerfiles par composant, chart Helm, étape ⑤ du pipeline (package + release),
`scripts/rollback.sh`, migrations par composant, preuves dans `docs/captures/images/` et
`docs/captures/rollback/`

### Décisions guidées par la mesure, non par la préférence

**1. Caddy → nginx-unprivileged.** Le Dockerfile fourni installait Caddy. À configuration
fonctionnelle équivalente, le scan des deux images officielles donne :

| Image | CVE HIGH/CRITICAL corrigibles |
|---|---|
| `caddy:2.11.2-alpine` | **55** |
| `nginxinc/nginx-unprivileged:1.29-alpine` | **10** |

**47 des 55** proviennent du binaire Go de Caddy, compilé avec une bibliothèque standard en retard.
nginx, écrit en C, n'expose pas cette surface — et sa variante *unprivileged* écoute nativement sur
8080 en utilisateur non privilégié, ce qui satisfait le constat A7 sans contorsion.

> **Ce que cela illustre** : le scan d'image ne sert pas seulement à bloquer une livraison. Il a
> orienté ici un **choix d'architecture**, sur une mesure et non sur une préférence.

**2. Spring Boot 3.2.5 → 3.5.16.** Le scan de l'image backend remontait 31 paquets vulnérables
(`spring-webmvc`, `tomcat-embed-core`, `jackson-databind`…). Contrairement au cas Angular de la
phase 3, les correctifs existaient **dans la même version majeure** : montée mineure, risque de
régression faible, tests verts après application. 31 → 3.

**3. `apk --no-cache upgrade` dans les étages d'exécution.** Restaient 13 CVE de paquets système
Alpine, corrigées dans les dépôts mais pas encore dans les images de base publiées. Deux options :

| Option | Effet | Retenue |
|---|---|---|
| Les accepter dans `.trivyignore.yaml` | L'image reste vulnérable en attendant une reconstruction amont, sur laquelle Orion n'a aucune prise | ❌ |
| Appliquer les correctifs à la construction | Les 13 CVE disparaissent réellement | ✅ |

**Compromis assumé** : la base reste épinglée par digest — le point de départ est déterministe —,
mais les paquets corrigés sont tirés au moment de la construction. Deux constructions éloignées
peuvent différer d'un niveau de correctif. C'est le bon arbitrage : sans cette ligne, l'image traîne
les CVE du jour de publication de sa base.

**Résultat cumulé : 0 vulnérabilité HIGH/CRITICAL corrigible sur les deux images** (31→0 et 55→0).
La porte de sécurité du pipeline peut donc rester stricte, sans aucune exception.

### Correction indispensable au déploiement : l'URL de l'API

Le frontend appelait `http://localhost:8080` **en dur** (`config.ts`). Ce choix fonctionne sur un
poste de développement mais rend l'application **indéployable** : le navigateur de l'utilisateur
résoudrait `localhost` vers sa propre machine.

Une ligne modifiée (`/api`), un relais nginx, et une variable `BACKEND_URL` injectée par Helm : la
**même image** fonctionne en local, sur Minikube et sur un cluster managé, sans reconstruction.
C'est l'application concrète du principe P3 « construire une fois, déployer partout ».

### Le tag d'image obligatoire, sans repli

Le helper Helm échoue si `image.tag` n'est pas fourni. J'avais d'abord prévu un repli sur
`.Chart.AppVersion` — puis constaté en test que le garde-fou en devenait inatteignable, et surtout
qu'il aurait fait déployer un tag d'image **jamais publié**, échouant en `ImagePullBackOff` : un
symptôme obscur, loin de sa cause. Le repli a été supprimé, et un job de CI vérifie désormais que le
garde-fou fonctionne toujours.

### Migrations par composant

Chaque composant exécute ses migrations dans **son propre Job Helm**, en hook `pre-upgrade`, avant
que les Deployments ne soient modifiés. Trois écueils évités : un composant sans base bloqué par la
migration d'un autre, une migration rejouée en concurrence par chaque réplique, une base à moitié
migrée servie par une application déjà à jour.

**Démonstration exécutée** : sur la version défectueuse, le Job échoue et `helm upgrade` s'arrête —
**aucun pod n'est remplacé**. C'est la différence avec la détection par les sondes :

| | Sondes | Hook de migration |
|---|---|---|
| Moment de détection | Après création du nouveau pod | **Avant** toute modification |
| État du cluster | Un pod défaillant existe | **Inchangé** |
| Action corrective | `helm rollback` nécessaire | **Aucune** |

**Le meilleur rollback est celui qu'on n'a pas besoin de faire.**

Précision assumée : c'est le **mécanisme** qui est démontré, pas un jeu de migrations réel — HSQLDB
est en mémoire (constat A1). Le Job exécute un contrôle d'intégrité de l'artefact, qui a
effectivement détecté la régression. La commande deviendra `flyway migrate` après migration vers
PostgreSQL, sans rien changer à l'ordonnancement.

### Les incidents de la phase, et leurs garde-fous

| # | Incident | Cause réelle | Correction — et garde-fou |
|---|---|---|---|
| 1 | Build Docker en **exit 127** | `app/back/gradlew` avait des fins de ligne **CRLF** dans ma copie locale : `#!/bin/sh\r`. Invisible en CI, où `.gitattributes` normalise à la sortie — mais bloquant pour tout build Docker local | Normalisation en LF. Le dépôt, lui, était sain : c'était la copie de travail Windows qui divergeait |
| 2 | Job release en échec | `npx --yes semantic-release@x @plugin@y` : npx interprétait les greffons comme des **arguments** (« Too many non-option arguments ») | Chaque paquet introduit par `-p` |
| 3 | Lint rouge sur `rollback.sh` | Fichier versionné en 644 | **Le garde-fou ajouté en phase 2 après l'incident `gradlew` l'a signalé dès l'étape de lint, avec la commande de correction exacte.** Le garde-fou a payé. |
| 4 | Fichiers `__pycache__/*.pyc` versionnés | Produits par mes vérifications locales de syntaxe Python | Retirés du suivi, ajoutés au `.gitignore` |

L'incident n°3 mérite d'être souligné : un garde-fou posé deux phases plus tôt, en réaction à un
autre incident, a attrapé exactement la même classe d'erreur sur un fichier différent. C'est ce que
doit produire une démarche DevOps — pas seulement corriger, mais **rendre l'erreur impossible à
répéter silencieusement**.

### Résultats mesurés

| Indicateur | Valeur |
|---|---|
| Exécution verte | [32165383499](https://github.com/Jihatech/oc-devops-p6-orion/actions/runs/32165383499) — **13/13 jobs** |
| Vulnérabilités des images | **0** (backend 31→0, frontend 55→0) |
| Release publiée | **v1.0.0**, changelog généré, tags `1.0.0` / `1.0` / `1` / `latest` |
| Images sur GHCR | Publiquement accessibles (vérifié anonymement : HTTP 200) |
| Rollback | **18 s**, vérifié par test de fumée |
| Interruption de service pendant l'échec | **Aucune** — 200 sur toutes les requêtes |
| Ressources Helm validées | 8 (kubeconform, 2 environnements) |

### Usage de l'IA en phase 4

| Usage | Nature |
|---|---|
| Rédaction des Dockerfiles, du chart et du workflow | **Assistée par IA**, sur une conception que j'ai arrêtée |
| Choix Caddy/nginx, Spring Boot, `apk upgrade` | **Miens** — pris sur des **scans réellement exécutés**, chiffres à l'appui |
| Diagnostic des 4 incidents | **Mien** — lecture des journaux d'exécution et des artefacts |
| Vérification | **Exécution réelle** : images construites et scannées, cluster Minikube, déploiement, échec provoqué, rollback, migrations — tout est journalisé dans `docs/captures/` |

**Point de méthode** : j'ai écrit un digest d'image **inventé** dans une première version du
Dockerfile backend. Je l'ai remplacé par les digests réellement résolus via `docker manifest
inspect` avant toute construction. Un digest plausible mais faux est pire qu'un tag : il donne
l'apparence de la rigueur sans en avoir la substance.

## Phase 5 — IaC, monitoring, DORA

*(à compléter)*

## Phase 6 — Consolidation des livrables

*(à compléter)*
