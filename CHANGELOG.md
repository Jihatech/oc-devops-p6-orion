# Journal des versions

Ce fichier est genere automatiquement par semantic-release a partir des messages de commit conventionnels. Ne pas le modifier a la main.

## [1.2.0](https://github.com/Jihatech/oc-devops-p6-orion/compare/v1.1.1...v1.2.0) (2026-08-18)

### Fonctionnalités

* **dora:** calculer les quatre indicateurs DORA sur les donnees reelles ([b60f637](https://github.com/Jihatech/oc-devops-p6-orion/commit/b60f63740bbd9b293106119dce51643b0fbadee7))
* **iac:** provisionner les environnements avec Terraform et Ansible ([34fea85](https://github.com/Jihatech/oc-devops-p6-orion/commit/34fea85fce029ba7de735617008a65deb58c2597))

## [1.1.1](https://github.com/Jihatech/oc-devops-p6-orion/compare/v1.1.0...v1.1.1) (2026-08-18)

### Corrections

* **preuves:** versionner les traces d'execution et interdire les liens morts ([793b2b0](https://github.com/Jihatech/oc-devops-p6-orion/commit/793b2b092ce8b4f18a86dd5be8ac5815df62e5d8))

## [1.1.0](https://github.com/Jihatech/oc-devops-p6-orion/compare/v1.0.0...v1.1.0) (2026-08-18)

### Fonctionnalités

* **helm:** ajouter les migrations par composant en hook pre-upgrade ([03e7f26](https://github.com/Jihatech/oc-devops-p6-orion/commit/03e7f26ac6a3efebef651e2305d2297744002c7a))

## 1.0.0 (2026-08-18)

### Fonctionnalités

* **ci:** ajouter l'etape package et le versionnement automatise ([6143879](https://github.com/Jihatech/oc-devops-p6-orion/commit/61438792d4af2d85affd264b3f66b0e7492dacd3))
* **docker:** durcir les images et les separer par composant ([1204df4](https://github.com/Jihatech/oc-devops-p6-orion/commit/1204df401f537096505a54d5542c9fa35782cb92))
* **helm:** deployer MicroCRM sur Kubernetes et automatiser le rollback ([d878fd3](https://github.com/Jihatech/oc-devops-p6-orion/commit/d878fd3eebb022855538fb48462ea8c429e79fa2))
* **scripts:** agreger les rapports JUnit des deux composants ([ab02b0f](https://github.com/Jihatech/oc-devops-p6-orion/commit/ab02b0fceff0f23709cbc5427abc2710a0f8749c))
* **scripts:** ajouter les scripts d'automatisation du pipeline ([3aba968](https://github.com/Jihatech/oc-devops-p6-orion/commit/3aba96894754d89315160f70a7ba2b14d28843eb))
* **securite:** integrer SonarQube et les controles Trivy dans le pipeline ([b063dd5](https://github.com/Jihatech/oc-devops-p6-orion/commit/b063dd57e0ccbba3ca1d11f21f88036869690224))
* **securite:** tracer 12 acceptations de risque explicites et datees ([324c369](https://github.com/Jihatech/oc-devops-p6-orion/commit/324c369616d20641f8e59b292a3bf7ea1f49cf95))

### Corrections

* **back:** restaurer le bit executable de gradlew ([66e8776](https://github.com/Jihatech/oc-devops-p6-orion/commit/66e8776734b109fc09c2cf6a0373a9823dcfe4cf))
* **ci:** corriger l'installation des greffons semantic-release ([97f8cf5](https://github.com/Jihatech/oc-devops-p6-orion/commit/97f8cf52717781e93c4e225d465045671b6bdad9))
* **docs:** corriger un libellé Mermaid empêchant le rendu du schéma de workflow ([d6d294d](https://github.com/Jihatech/oc-devops-p6-orion/commit/d6d294d95aac4b686e38c1937bc65f11b6b9e445))
* **front:** regenerer le verrou npm sans --legacy-peer-deps ([094c88d](https://github.com/Jihatech/oc-devops-p6-orion/commit/094c88d591fb7b9ab5a07907155d73778d0c37be))
* **front:** supprimer l'import inutilise de Router ([1946faa](https://github.com/Jihatech/oc-devops-p6-orion/commit/1946faa79ff32ddb2eee618b5593d158927512b7))
* **qualite:** corriger les 4 defauts remontes par SonarQube ([6b391eb](https://github.com/Jihatech/oc-devops-p6-orion/commit/6b391ebc86216a2111b1922399cd319ee5e345e9))
* **scripts:** remplacer un enchainement A && B || C par un bloc if explicite ([fd327ee](https://github.com/Jihatech/oc-devops-p6-orion/commit/fd327ee1001040bfba0a239c140c6beef8662252))
* **scripts:** restaurer le bit executable de rollback.sh et exclure les .pyc ([349dcb7](https://github.com/Jihatech/oc-devops-p6-orion/commit/349dcb7def0ad7ecbaa730cbc3562373f11d5bd1))
* **scripts:** traiter les attributs JUnit absents dans l'agregation ([db816dd](https://github.com/Jihatech/oc-devops-p6-orion/commit/db816dd3fedfda55e151eae162ed5654e0dacd67))
* **securite:** corriger deux vulnerabilites critiques des dependances ([a5f8995](https://github.com/Jihatech/oc-devops-p6-orion/commit/a5f89953d1ad5c4c84ef239859adcd271cde92cf))
* **securite:** corriger un echec du scan lorsqu'aucune vulnerabilite n'est trouvee ([bc6d7a9](https://github.com/Jihatech/oc-devops-p6-orion/commit/bc6d7a901f89038fa12dbfa38d1ea07cf7f1f001))
* **securite:** fiabiliser la recuperation du verdict SonarQube ([31b6f03](https://github.com/Jihatech/oc-devops-p6-orion/commit/31b6f0328813bd2644b5cdd01d55237e9022f4af))

### Construction et dépendances

* **app:** intégrer l'application MicroCRM fournie par OpenClassrooms ([7f176df](https://github.com/Jihatech/oc-devops-p6-orion/commit/7f176dfe40ea6e6043c4926af0313e66a73974ec))
* **back:** activer JaCoCo et supprimer une dependance dupliquee ([474f025](https://github.com/Jihatech/oc-devops-p6-orion/commit/474f0251ad63947fc4f3b1dc19b0809cd7a07d18))
* **front:** introduire ESLint pour l'analyse statique du frontend ([f031e23](https://github.com/Jihatech/oc-devops-p6-orion/commit/f031e2386124f8f223058e1040a9807c2bff72cc))
