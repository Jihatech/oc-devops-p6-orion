# Orion — Chaîne CI/CD MicroCRM

> **Projet 6 — « Gérez une démarche DevOps » (Option B)** — parcours OpenClassrooms **Expert DevOps**
> Industrialisation complète de la chaîne CI/CD de l'application Full-Stack **MicroCRM** d'Orion.
> Auteur : **Ilyasse JAIEL**

[![CI](https://github.com/Jihatech/oc-devops-p6-orion/actions/workflows/ci.yml/badge.svg)](https://github.com/Jihatech/oc-devops-p6-orion/actions/workflows/ci.yml)

---

## En une page

Orion disposait d'une chaîne qui **vérifiait le code mais ne livrait rien** : les images Docker,
seul artefact réel, étaient construites, contrôlées et déployées à la main par deux personnes. Une
vulnérabilité détectée trop tard avait déjà retardé un déploiement.

Le projet transforme cette chaîne en un dispositif qui **produit, contrôle, publie, déploie et sait
revenir en arrière**.

| Indicateur | Avant | Après |
|---|---|---|
| Contrôles de sécurité automatisés | 0 | **5** |
| Délai de détection d'une vulnérabilité | Plusieurs jours | **Quelques minutes** |
| Vulnérabilités dans les images livrées | 86 | **0** |
| Retour à la version précédente | Impossible | **18 s, sans interruption** |
| Versions livrées identifiables | Non | **5 releases tracées** |

---

## Démarrage rapide

> Objectif : cloner, tout relancer, sans rien demander à personne.

### Prérequis

| Outil | Version validée |
|---|---|
| Docker | 28.5.1 |
| Minikube | 1.38.1 |
| kubectl | 1.34.1 |
| Helm | 4.2.3 |
| Terraform | 1.15.6 |
| Node.js / npm | 20.19 (CI) — 25.2 (poste) |
| Java (JDK) | 17 |
| Python | 3.11 |

Vérification automatique de la chaîne d'outils :

```bash
ansible-playbook ansible/prerequis.yml
```

### 1. Tests et qualité, sans cluster

```bash
./scripts/install-deps.sh                    # dépendances des deux composants
./scripts/run-tests.sh --sortie reports      # tests + couverture
bash_unit scripts/tests/test_commun.sh       # 31 tests des scripts
./scripts/scan-securite.sh                   # dépendances, secrets, configurations
```

### 2. Analyse SonarQube complète

```bash
./scripts/sonar-analyse.sh --demarrer --arreter
```

Serveur démarré en conteneur, analysé, puis détruit. Aucun compte, aucun secret : les preuves
d'analyse sont écrites dans [`docs/captures/sonarqube/`](docs/captures/sonarqube/).

### 3. Déploiement sur Kubernetes

```bash
# Cluster local et images
minikube start --driver=docker --cpus=2 --memory=3g
eval $(minikube -p minikube docker-env --shell bash)
docker build -f app/back/Dockerfile  -t orion-microcrm-back:1.3.0  app/
docker build -f app/front/Dockerfile -t orion-microcrm-front:1.3.0 app/

# Environnements provisionnés par Terraform (namespaces, quotas, politiques réseau)
terraform -chdir=terraform init
terraform -chdir=terraform apply

# Déploiement — le tag d'image est OBLIGATOIRE, le chart refuse un tag implicite
helm upgrade --install microcrm helm/microcrm -n orion-dev \
    -f helm/microcrm/values-dev.yaml --set image.tag=1.3.0 --wait

# Accès
kubectl port-forward -n orion-dev svc/microcrm-front 8081:8080
#   → http://localhost:8081   (le frontend relaie /api vers le backend)
```

### 4. Retour arrière vérifié

```bash
./scripts/rollback.sh --release microcrm --namespace orion-dev
```

### 5. Observabilité

```bash
docker compose -f elk/docker-compose.yml up -d     # Elasticsearch, Kibana, Filebeat
kubectl apply -f elk/k8s/filebeat-daemonset.yaml    # journaux des pods
./scripts/elk-setup.sh                              # vues, tableaux de bord, alertes
#   → http://localhost:5601/app/dashboards
```

### 6. Indicateurs DORA

```bash
export GITHUB_TOKEN=$(gh auth token)
python3 scripts/dora-metrics.py --depot Jihatech/oc-devops-p6-orion
```

---

## L'application industrialisée

**MicroCRM** — CRM simplifié (personnes ↔ organisations), fourni par OpenClassrooms.

| Composant | Stack | Build | Tests |
|---|---|---|---|
| [`app/front`](app/front/) | Angular 17 / TypeScript | `ng build` | Karma + Jasmine |
| [`app/back`](app/back/) | Spring Boot 3.5.16 / Java 17 | `gradlew build` | JUnit 5 |
| Base de données | HyperSQL, en mémoire | — | — |

Artefacts de livraison : **2 images Docker** publiées sur GHCR, **publiquement accessibles** :

```
ghcr.io/jihatech/oc-devops-p6-orion/orion-microcrm-back:1.3.0
ghcr.io/jihatech/oc-devops-p6-orion/orion-microcrm-front:1.3.0
```

---

## Le pipeline

Défini dans [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — **13 jobs**, environ 7 minutes.

```
① lint  →  ② build  →  ③ test  →  ④ security  →  ⑤ package  →  déploiement Helm
```

| Étape | Jobs | Contrôles |
|---|---|---|
| ① lint | `lint-front`, `lint-scripts`, `lint-manifestes` | ESLint · ShellCheck · syntaxe Python · bits exécutables · **liens de documentation** · `helm lint` · `terraform validate` · `ansible-lint` · kubeconform |
| ② build | `build-front`, `build-back` | Bundle Angular · JAR Spring Boot, publiés en artefacts |
| ③ test | `test-front`, `test-back`, `test-scripts` | Karma + LCOV · JUnit + JaCoCo · 31 tests bash_unit · **cycle sauvegarde → restauration vérifié** |
| ④ security | `sonarqube`, `scan-securite` | SonarQube (SAST + hotspots + **quality gate bloquante**) · `npm audit` · Trivy `fs`, `secret`, `config` |
| ⑤ package | `package`, `release` | `docker build` → **scan Trivy bloquant** → push GHCR · semantic-release |
| — | `notification` | Synthèse dans l'onglet Actions, **issue de suivi sur échec** |

### Les trois points d'architecture à retenir

1. **Le scan Trivy se situe entre `docker build` et `docker push`, dans le même job.** Une image
   vulnérable n'atteint donc jamais le registre. Le placer dans un job ultérieur aurait été plus
   simple à écrire, mais inopérant : l'image serait déjà publiée au moment du verdict.
2. **Le pipeline appelle les scripts, il ne réimplémente pas leur logique.** Un développeur reproduit
   exactement le comportement de la chaîne sur son poste.
3. **Les images ne sont jamais reconstruites à la release.** Les tags sémantiques sont ajoutés au
   manifeste déjà publié : l'artefact promu est, au bit près, celui qui a été testé et scanné.

### Résultats de la dernière exécution

| Indicateur | Valeur |
|---|---|
| Tests | 10 applicatifs (100 %) · **31** tests de scripts |
| Couverture | backend **65,9 %** · frontend **30,8 %** · projet **37,4 %** |
| Quality gate SonarQube | ✅ OK — 0 vulnérabilité, 0 hotspot, **0 bug**, notes **A/A/A** |
| Sécurité des images | **0 vulnérabilité** HIGH/CRITICAL corrigible |
| Sécurité des dépendances | 0 critique en production · 12 CVE acceptées, datées |
| Lint | 0 erreur ESLint (10 avertissements suivis) · 0 défaut ShellCheck |

---

## Documentation

| Document | Contenu |
|---|---|
| [`01-audit-swot.md`](docs/01-audit-swot.md) | Audit du processus existant : SWOT, goulots, lacunes mappées OWASP |
| [`02-veille-recommandations.md`](docs/02-veille-recommandations.md) | 8 familles d'outils comparées, **9 solutions écartées**, priorisation MoSCoW |
| [`03-normalisation-plan-ci.md`](docs/03-normalisation-plan-ci.md) | Structure du pipeline, **ordre d'exécution argumenté**, portes de qualité |
| [`04-plan-tests.md`](docs/04-plan-tests.md) | 16 types de tests, exclusions motivées, seuils chiffrés |
| [`05-plan-securite.md`](docs/05-plan-securite.md) | Contrôles, secrets, **OWASP Top 10**, risques résiduels |
| [`06-architecture.md`](docs/06-architecture.md) | 4 schémas — CI/CD, infrastructure locale, **cloud cible**, secrets |
| [`07-plan-releases-rollback-backup.md`](docs/07-plan-releases-rollback-backup.md) | Releases, versions entre environnements, **rollback**, sauvegarde |
| [`08-rapport-performance-matiere.md`](docs/08-rapport-performance-matiere.md) | **Avant / après**, DORA, gains, retours d'expérience, recommandations |
| [`09-evolution-cloud.md`](docs/09-evolution-cloud.md) | Migration vers le cloud : étapes, **coûts**, risques, multi-cloud |
| [`10-conformite-et-soutenance.md`](docs/10-conformite-et-soutenance.md) | **Conformité à la fiche** et réponses aux 6 questions de soutenance |
| [`JOURNAL_IA.md`](docs/JOURNAL_IA.md) | Méthodologie, décisions, incidents, usage de l'IA |

### Preuves d'exécution

| Répertoire | Contenu |
|---|---|
| [`captures/sonarqube/`](docs/captures/sonarqube/) | Analyses et **comparaison avant/après** — bugs 2 → 0, fiabilité C → A |
| [`captures/images/`](docs/captures/images/) | Durcissement des images — **86 → 0** vulnérabilités |
| [`captures/rollback/`](docs/captures/rollback/) | Rollback et migrations — démonstrations exécutées sur Minikube |
| [`captures/iac/`](docs/captures/iac/) | Terraform et Ansible — apply, idempotence, lint profil production |
| [`captures/elk/`](docs/captures/elk/) | Stack ELK — index, tableaux de bord, alertes, données agrégées |
| [`captures/dora/`](docs/captures/dora/) | Indicateurs DORA mesurés sur l'historique réel du dépôt |

---

## Structure du dépôt

```
├── .github/workflows/   # Pipeline CI/CD (13 jobs)
├── app/                 # Application MicroCRM fournie
│   ├── front/           # Angular 17 + Dockerfile multi-étages
│   └── back/            # Spring Boot 3 + Dockerfile multi-étages
├── scripts/             # 13 scripts d'automatisation (Bash + Python)
├── helm/microcrm/       # Chart Helm, values par environnement
├── terraform/           # Modules IaC — namespaces, quotas, politiques réseau
├── ansible/             # 3 playbooks — prérequis, déploiement, sauvegarde
├── elk/                 # Stack d'observabilité entièrement en code
└── docs/                # Documentation, journal et preuves d'exécution
```

---

## Scripts d'automatisation

Chaque script porte en tête sa documentation complète — **BUT, FONCTIONNEMENT, PARAMÈTRES,
CONDITIONS D'EXÉCUTION** —, ses exemples et ses codes de sortie. `--aide` l'affiche.

| Script | Rôle |
|---|---|
| [`lib/commun.sh`](scripts/lib/commun.sh) | Bibliothèque partagée — **fonctions pures testées** |
| [`install-deps.sh`](scripts/install-deps.sh) | Installation déterministe, mode hors ligne |
| [`run-tests.sh`](scripts/run-tests.sh) | Tests + collecte JUnit, LCOV, JaCoCo |
| [`deploy-build.sh`](scripts/deploy-build.sh) | Déploiement Docker avec test de fumée et rollback |
| [`rollback.sh`](scripts/rollback.sh) | Retour à N-1, **avec vérification du service** |
| [`backup.sh`](scripts/backup.sh) | Sauvegarde vérifiée (SHA-256, manifeste) **et restauration** |
| [`scan-securite.sh`](scripts/scan-securite.sh) | Dépendances, secrets, configurations |
| [`sonar-analyse.sh`](scripts/sonar-analyse.sh) | Analyse SonarQube — serveur éphémère, jeton généré |
| [`sonar-report.py`](scripts/sonar-report.py) | Quality gate et export des preuves |
| [`dora-metrics.py`](scripts/dora-metrics.py) | Les 4 indicateurs DORA — JSON, CSV, Markdown, NDJSON |
| [`notify.py`](scripts/notify.py) | Synthèse de pipeline, issue sur échec |
| [`elk-setup.sh`](scripts/elk-setup.sh) | Configuration reproductible d'ELK |
| [`verifier-liens.py`](scripts/verifier-liens.py) | Interdit les liens morts dans la documentation |

### Contrôles qualité

```bash
shellcheck --shell=bash --severity=style --external-sources \
    scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh   # 0 défaut
bash_unit scripts/tests/test_commun.sh                 # 31 tests
python3 scripts/verifier-liens.py                      # 0 lien mort
```

La **décision** de purge des sauvegardes est isolée dans une fonction pure, séparée de son
**exécution**, et couverte par des tests de cas limites : rétention nulle, négative, non numérique,
égalité stricte. Un défaut à cet endroit détruirait des sauvegardes.

---

## Ce que garantit le déploiement

| Garantie | Mécanisme |
|---|---|
| Aucune interruption pendant une mise à jour | `RollingUpdate` avec `maxUnavailable: 0` |
| Un pod défaillant ne reçoit jamais de trafic | `startupProbe` + `readinessProbe` |
| Une migration impossible bloque **avant** tout déploiement | Job Helm `pre-upgrade` par composant |
| Impossible de déployer une version non identifiable | `image.tag` obligatoire, sans repli |
| Retour arrière vérifié | `rollback.sh` + test de fumée |
| Aucune image vulnérable au registre | Scan Trivy **entre** build et push |

---

## Conventions

- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/) en français —
  `<type>(<portée>): <description>`. Ils pilotent `semantic-release`.
- **Branches** : trunk-based. Modèle comparé et justifié dans
  [`03-normalisation-plan-ci.md`](docs/03-normalisation-plan-ci.md) §2.1, qui documente aussi
  l'écart entre le modèle cible pour Orion et ce qui a été pratiqué sur ce projet solo.
- **Versions** : sémantiques, déduites des commits. Un déploiement référence **toujours** un tag
  immuable.
- **Sécurité** : **aucun credential versionné**. Secrets en GitHub Secrets et Secrets Kubernetes,
  permissions de workflow minimales, jetons éphémères.

---

## Écarts assumés

Documentés en détail dans [`10-conformite-et-soutenance.md`](docs/10-conformite-et-soutenance.md) §6.

| Écart | Motif |
|---|---|
| GitHub plutôt que GitLab | Fiche : « GitLab **ou équivalent** » ; validé par le mentor ; table de correspondance fournie |
| SonarQube en conteneur plutôt que SonarCloud | Aucune dépendance externe, aucun secret : l'évaluateur relance tout |
| Minikube plutôt qu'un cluster managé | ~180 €/mois sans bénéfice hors production ; migration chiffrée dans le document 09 |
| Base HSQLDB conservée | Développement applicatif, hors périmètre — **recommandation n°1** |
| API sans authentification | Même motif ; signalée comme **risque critique** |
| 12 CVE acceptées | Correctif à deux versions majeures ; acceptations **datées au 30/11/2026** |
| Couverture à 37,4 % | L'application est arrivée sans tests exploitables ; axe d'amélioration chiffré |
