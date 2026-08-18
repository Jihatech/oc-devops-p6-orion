# Orion — Chaîne CI/CD MicroCRM

> **Projet 6 — « Gérez une démarche DevOps » (Option B)** — parcours OpenClassrooms **Expert DevOps**
> Industrialisation complète de la chaîne CI/CD de l'application Full-Stack **MicroCRM** d'Orion.
> Auteur : **Ilyasse JAIEL**

---

## État d'avancement

| Phase | Contenu | Statut |
|---|---|---|
| 1 | Audit, veille, normalisation du pipeline | ✅ **Terminée** |
| 2 | Pipeline CI + scripts d'automatisation | ✅ **Terminée** — [pipeline vert](https://github.com/Jihatech/oc-devops-p6-orion/actions) |
| 3 | DevSecOps — SonarQube, Trivy, plans de tests et de sécurité | ✅ **Terminée** |
| 4 | Conteneurisation, Kubernetes + Helm, releases et rollback | ⏳ À venir |
| 5 | Terraform, Ansible, ELK, métriques DORA | ⏳ À venir |
| 6 | Consolidation des livrables finaux | ⏳ À venir |

## L'application industrialisée

**MicroCRM** — CRM simplifié (personnes ↔ organisations), fourni par OpenClassrooms.

| Composant | Stack | Build | Tests |
|---|---|---|---|
| `app/front` | Angular 17 / TypeScript | `ng build` (npm) | Karma + Jasmine |
| `app/back` | Spring Boot 3.2.5 / Java 17 | `gradlew build` | JUnit 5 |
| Base de données | HyperSQL (en mémoire) | — | — |

Artefacts de livraison : **2 images Docker** (`front`, `back`) publiées sur **GHCR**.

## Structure du dépôt

```
├── .github/workflows/   # Pipeline CI/CD (GitHub Actions)
├── app/                 # Application MicroCRM fournie
│   ├── front/           # Angular 17
│   ├── back/            # Spring Boot 3 (Gradle)
│   └── Dockerfile       # Multi-stage : front · back · standalone
├── scripts/             # Scripts d'automatisation (Bash + Python)
├── helm/                # Charts Helm, values par environnement
├── terraform/           # Modules IaC commentés
├── ansible/             # Playbooks de provisionnement et d'exploitation
├── elk/                 # Stack de journalisation + tableaux de bord Kibana
└── docs/                # Documentation du projet
    ├── contexte/        # Sondages Orion (sources primaires)
    ├── captures/        # Captures d'écran (ELK, SonarQube, pipeline, DORA)
    └── JOURNAL_IA.md    # Journal de méthodologie et d'usage de l'IA
```

## Documentation

| Document | Contenu |
|---|---|
| [`docs/01-audit-swot.md`](docs/01-audit-swot.md) | Audit du processus CI existant : SWOT, goulots d'étranglement, lacunes de sécurité mappées OWASP |
| [`docs/02-veille-recommandations.md`](docs/02-veille-recommandations.md) | Veille comparative (8 familles d'outils), recommandations argumentées, solutions **écartées**, priorisation MoSCoW |
| [`docs/03-normalisation-plan-ci.md`](docs/03-normalisation-plan-ci.md) | Structure cible du pipeline, **ordre d'exécution argumenté**, portes de qualité, schémas Mermaid |
| [`docs/04-plan-tests.md`](docs/04-plan-tests.md) | 16 types de tests (périmètre, outil, fréquence, critères), exclusions motivées, seuils chiffrés |
| [`docs/05-plan-securite.md`](docs/05-plan-securite.md) | Objectifs, contrôles, gestion des secrets, **mapping OWASP Top 10**, réponse à incident, risques résiduels |
| [`docs/captures/sonarqube/`](docs/captures/sonarqube/) | **Preuves d'analyse et comparaison avant/après** |
| [`docs/JOURNAL_IA.md`](docs/JOURNAL_IA.md) | Méthodologie, décisions et arbitrages, usage de l'IA |

## Chaîne cible en un coup d'œil

```
① lint  →  ② build  →  ③ test  →  ④ security  →  ⑤ package  →  déploiement Helm
```

- **Sécurité en amont** : SonarQube (SAST + security hotspots), `npm audit`, Trivy (`fs`, `image`, `config`).
- **Aucune image vulnérable ne peut atteindre le registre** : le scan Trivy est effectué **entre** la
  construction et la publication.
- **Traçabilité** : commit conventionnel → `semantic-release` → tag sémantique → tag d'image → release
  déployée.
- **Réversibilité** : `helm rollback` vers la version N-1, documenté **et testé**.

## Prérequis (environnement de développement)

| Outil | Version validée |
|---|---|
| Docker | 28.5.1 |
| Minikube / kubectl / Helm | — |
| Terraform | 1.15.6 |
| Node.js / npm | 25.2.1 / 11.6.2 |
| Java (JDK) | 17 |
| Python | 3.11 |
| Git | 2.54 |

## Conventions

- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/) en français —
  `<type>(<portée>): <description>`. Ils pilotent `semantic-release`.
- **Branches** : trunk-based — `main` protégée, branches courtes `feat/*`, `fix/*`, `chore/*`.
- **Sécurité** : **aucun credential versionné**. Secrets en GitHub Secrets et Secrets Kubernetes ;
  permissions de workflow minimales.

---

## Pipeline d'intégration continue

Défini dans [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — **10 jobs**.

| Étape | Jobs | Contrôles |
|---|---|---|
| ① lint | `lint-front`, `lint-scripts` | ESLint · ShellCheck (version épinglée) · syntaxe Python · bits exécutables |
| ② build | `build-front`, `build-back` | Bundle Angular de production · JAR Spring Boot — publiés en artefacts |
| ③ test | `test-front`, `test-back`, `test-scripts` | Karma + LCOV · JUnit + JaCoCo · 31 tests bash_unit · **cycle sauvegarde → restauration vérifié** |
| ④ security | `sonarqube`, `scan-securite` | SonarQube (SAST + hotspots + **quality gate bloquante**) · `npm audit` · Trivy `fs`, `secret`, `config` |
| — | `notification` | Synthèse Markdown dans l'onglet Actions, issue de suivi sur échec |

L'étape ⑤ *package* (GHCR, semantic-release) arrive en phase 4.

**Résultats de la dernière exécution** :

| Indicateur | Valeur |
|---|---|
| Tests | **10** (8 front + 2 back), 100 % de réussite · **31** tests bash_unit |
| Couverture | backend **65,9 %** · frontend **30,8 %** · projet **37,4 %** |
| Quality gate SonarQube | ✅ OK — 0 vulnérabilité, 0 hotspot, **0 bug**, note de sécurité **A** |
| Lint | 0 erreur ESLint (10 avertissements suivis) · 0 défaut ShellCheck |
| Sécurité des dépendances | 0 critique en production · **12 CVE acceptées explicitement et datées** |

## Scripts d'automatisation

Chaque script porte en tête sa documentation complète : **BUT, FONCTIONNEMENT, PARAMÈTRES,
CONDITIONS D'EXÉCUTION**, exemples et codes de sortie. `--aide` l'affiche.

| Script | Rôle |
|---|---|
| [`scripts/lib/commun.sh`](scripts/lib/commun.sh) | Bibliothèque partagée — journalisation, prérequis, **fonctions pures testées** |
| [`scripts/install-deps.sh`](scripts/install-deps.sh) | Installation déterministe (`npm ci`, résolution Gradle), mode hors ligne |
| [`scripts/run-tests.sh`](scripts/run-tests.sh) | Tests + collecte des rapports JUnit, LCOV et JaCoCo |
| [`scripts/deploy-build.sh`](scripts/deploy-build.sh) | Déploiement Docker avec **test de fumée et rollback automatique** |
| [`scripts/backup.sh`](scripts/backup.sh) | Sauvegarde vérifiée (SHA-256 + manifeste) **et restauration** |
| [`scripts/notify.py`](scripts/notify.py) | Synthèse de pipeline — GitHub Summary, issue sur échec (sans dépendance externe) |
| [`scripts/scan-securite.sh`](scripts/scan-securite.sh) | Contrôles de sécurité — dépendances, secrets, configurations |
| [`scripts/sonar-analyse.sh`](scripts/sonar-analyse.sh) | Analyse SonarQube — serveur éphémère, jeton généré à l'exécution |
| [`scripts/sonar-report.py`](scripts/sonar-report.py) | Quality gate et export des preuves d'analyse |

### Utilisation locale (reproductible)

```bash
# 1. Dépendances des deux composants
./scripts/install-deps.sh

# 2. Tests avec couverture, rapports dans reports/
./scripts/run-tests.sh --sortie reports

# 3. Synthèse lisible des résultats
python3 scripts/notify.py --statut succes --rapports reports --canal console

# 4. Sauvegarde (rétention : 7 archives) puis restauration vérifiée
./scripts/backup.sh --retention 7
./scripts/backup.sh --mode restauration \
    --archive backups/microcrm_<horodatage>.tar.gz --cible /tmp/restaure

# 5. Déploiement local Docker, avec test de fumée et rollback si échec
./scripts/deploy-build.sh --environnement dev
```

### Contrôles qualité des scripts

```bash
shellcheck --shell=bash --severity=style --external-sources \
    scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh   # 0 défaut

bash_unit scripts/tests/test_commun.sh                 # 31 tests
```

### Contrôles de sécurité

```bash
./scripts/scan-securite.sh                             # dépendances, secrets, configurations
./scripts/sonar-analyse.sh --demarrer --arreter        # analyse SonarQube complète
```

Les acceptations de risque sont tracées dans [`.trivyignore.yaml`](.trivyignore.yaml) : chacune porte
une justification et une **date d'expiration**. Le seuil bloquant reste à `HIGH` — **toute nouvelle
vulnérabilité bloque le pipeline**.

La **décision** de purge des sauvegardes est isolée dans une fonction pure, séparée de son
**exécution**, et couverte par des tests de cas limites (rétention nulle, négative, non numérique,
égalité stricte) : un défaut à cet endroit détruirait des sauvegardes.

---

> Les instructions de déploiement Kubernetes seront ajoutées en phase 4.
