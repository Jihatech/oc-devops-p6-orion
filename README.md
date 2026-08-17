# Orion — Chaîne CI/CD MicroCRM

> **Projet 6 — « Gérez une démarche DevOps » (Option B)** — parcours OpenClassrooms **Expert DevOps**
> Industrialisation complète de la chaîne CI/CD de l'application Full-Stack **MicroCRM** d'Orion.
> Auteur : **Ilyasse JAIEL**

---

## État d'avancement

| Phase | Contenu | Statut |
|---|---|---|
| 1 | Audit, veille, normalisation du pipeline | ✅ **Terminée** |
| 2 | Pipeline CI + scripts d'automatisation | ⏳ À venir |
| 3 | DevSecOps — SonarQube, Trivy, plans de tests et de sécurité | ⏳ À venir |
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

> Les instructions de déploiement reproductibles seront ajoutées au fil des phases 2 à 6.
