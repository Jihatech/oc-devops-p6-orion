# 07 — Plan d'automatisation des releases, de rollback et de sauvegarde

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Objet** : décrire les procédures de mise en production, de retour arrière et de sauvegarde —
> toutes **exécutées et vérifiées**, pas seulement décrites.
>
> **Accessibilité** : ce document suit une structure de titres hiérarchisée, n'utilise que des
> tableaux simples sans cellules fusionnées, et accompagne chaque schéma d'une description
> textuelle (exigence PSH du guide mentor).

---

## Sommaire

1. [Situation de départ](#1-situation-de-départ)
2. [Automatisation des releases](#2-automatisation-des-releases)
3. [Gestion des versions entre environnements](#3-gestion-des-versions-entre-environnements)
4. [Procédure de rollback](#4-procédure-de-rollback)
5. [Plan de sauvegarde et de restauration](#5-plan-de-sauvegarde-et-de-restauration)
6. [Procédures d'exploitation](#6-procédures-dexploitation)
7. [Ce qui reste à faire](#7-ce-qui-reste-à-faire)

---

## 1. Situation de départ

L'audit a établi trois manques qui rendaient toute mise en production risquée.

| Réf. | Constat | Conséquence |
|---|---|---|
| **f4** | Version figée à `0.0.1-SNAPSHOT`, aucun tag, aucun artefact conservé | La question « quelle version tourne ? » était sans réponse |
| **f8** | Ni sauvegarde, ni procédure de restauration, ni retour arrière | Un incident en production aurait été ingérable |
| **G4** | Transmission du numéro de version par courriel | Latence humaine, aucun historique |

Les trois procédures décrites ci-dessous répondent à ces manques, et chacune a été **exécutée**.

---

## 2. Automatisation des releases

### 2.1 Principe

La version n'est pas décidée : elle est **déduite** du contenu des commits. C'est ce qui supprime
l'erreur humaine que le processus manuel produisait.

| Type de commit | Effet sur la version | Exemple |
|---|---|---|
| `fix:` | Incrément de correctif | 1.2.0 vers 1.2.1 |
| `feat:` | Incrément mineur | 1.2.1 vers 1.3.0 |
| `BREAKING CHANGE:` | Incrément majeur | 1.3.0 vers 2.0.0 |
| `docs:`, `ci:`, `test:` | Aucun | La documentation ne crée pas de version |

### 2.2 Déclenchement

Une release est produite automatiquement à chaque fusion sur `main`, **et seulement si** les cinq
étapes du pipeline sont vertes. Aucun déclenchement manuel n'existe : une version ne peut donc pas
naître d'un état non vérifié.

### 2.3 Ce que produit une release

| Production | Contenu |
|---|---|
| Tag Git | `v1.3.0` |
| Changelog | `CHANGELOG.md`, généré et commité automatiquement |
| Release GitHub | Notes de version issues des commits |
| Tags d'images | `1.3.0`, `1.3`, `1`, `latest` |

### 2.4 La règle qui garantit l'intégrité

> **Les images ne sont jamais reconstruites au moment de la release.**

Les tags sémantiques sont ajoutés au manifeste déjà publié, par `docker buildx imagetools create`.
L'artefact promu est donc, **au bit près**, celui qui a été testé et scanné.

Reconstruire produirait une image différente — horodatages, couches, versions de paquets système —
et l'on promouvrait alors un artefact que rien n'a validé.

### 2.5 Résultat observé

Cinq releases ont été produites automatiquement pendant le projet : `v1.0.0`, `v1.1.0`, `v1.1.1`,
`v1.2.0`, `v1.3.0`. Aucune n'a nécessité d'intervention manuelle.

---

## 3. Gestion des versions entre environnements

### 3.1 Règle de nommage

| Tag | Usage | Mutable ? |
|---|---|---|
| `sha-a1b2c3d` | Identifie un commit précis | Non |
| `1.3.0` | Release sémantique | Non |
| `1.3`, `1` | Alias de commodité | Oui |
| `latest` | Dernière release | Oui |

### 3.2 La règle de déploiement

> **Un déploiement référence toujours un tag immuable** : `sha-` ou une version sémantique exacte.
> Jamais `latest`, jamais un alias.

Cette règle est **imposée techniquement**, pas seulement recommandée : le chart Helm refuse de
produire ses manifestes si `image.tag` n'est pas fourni explicitement. Un job du pipeline vérifie
d'ailleurs que ce garde-fou fonctionne toujours.

Déployer un alias mutable ramènerait exactement la faiblesse f4 : impossible de savoir ce qui
tourne, et rollback sans cible fiable.

### 3.3 Promotion entre environnements

| Environnement | Source de l'image | Déclenchement | Répliques |
|---|---|---|---|
| **dev** | Démon Docker local | Manuel, par l'opérateur | 1 |
| **staging** | GHCR | Automatique après une release | 2 |
| **prod** | GHCR, tag sémantique exact | **Manuel et délibéré** | À dimensionner |

**La même image traverse les trois environnements.** Rien n'est reconstruit entre eux : seules les
valeurs Helm changent (répliques, quotas, ressources). C'est le principe « construire une fois,
déployer partout ».

Deux répliques en staging ne sont pas un luxe : elles permettent de vérifier que la mise à jour
progressive fonctionne réellement, ce qu'une réplique unique ne démontre pas.

---

## 4. Procédure de rollback

### 4.1 Deux barrières, pas une

L'architecture met en place **deux mécanismes de protection successifs**, qui n'interviennent pas au
même moment.

| Barrière | Moment | Ce qu'elle attrape | État du cluster si déclenchée |
|---|---|---|---|
| **Job de migration** (`pre-upgrade`) | Avant toute modification | Artefact corrompu, migration impossible, base injoignable | **Inchangé** — aucun pod remplacé |
| **Sondes** (`startup`, `readiness`) | Après création du nouveau pod | Défaut qui n'apparaît qu'à l'exécution | Un pod défaillant existe, sans trafic |

> **Le meilleur rollback est celui qu'on n'a pas besoin de faire.** La première barrière évite
> l'opération entière ; la seconde la rend sûre quand elle est inévitable.

### 4.2 Deux modes de retour arrière

| Mode | Commande | Quand l'utiliser |
|---|---|---|
| **Automatique** | `helm upgrade --atomic` | Déploiement non surveillé, par exemple depuis la CI |
| **Piloté** | `./scripts/rollback.sh` | Incident constaté après coup, décision humaine, trace exigée |

### 4.3 Ce que fait le script de rollback

Le script ne se contente pas d'appeler `helm rollback`. Il enchaîne six actions :

1. Affiche l'historique de la release et l'état des pods, pour tracer la situation de départ.
2. **Détermine la dernière révision saine** — jamais une révision en échec, qui restaurerait une
   version déjà cassée.
3. Exécute `helm rollback --wait`, qui attend que les pods restaurés soient réellement prêts.
4. Réaffiche l'état des pods et l'historique.
5. **Vérifie par un test HTTP** que le service répond, frontend et API.
6. Écrit une trace horodatée de l'opération.

L'étape 5 est celle qui distingue une procédure d'une intention : une release marquée « deployed »
dont le service ne répond pas **n'est pas** un rollback réussi.

### 4.4 Résultat mesuré

La procédure a été exécutée en conditions réelles, avec une régression volontaire (artefact
corrompu).

| Mesure | Valeur |
|---|---|
| Durée du rollback, vérification comprise | **18 secondes** |
| Interruption de service pendant l'échec | **Aucune** — 200 sur toutes les requêtes |
| Révision cible choisie | La dernière saine, automatiquement |

**Preuves** : [`docs/captures/rollback/`](captures/rollback/) — journal de la démonstration, trace du
rollback, journal des migrations.

### 4.5 L'historique reste complet

Un rollback Helm ne supprime rien : il crée une **nouvelle révision** dont le contenu est celui de
la révision cible.

| Révision | Statut | Description |
|---|---|---|
| 1 | superseded | Install complete |
| 2 | **failed** | Upgrade échoué : ressource non prête |
| 3 | deployed | Rollback vers la révision 1 |

L'échec reste visible en révision 2. On ne peut pas effacer un mauvais déploiement de l'historique —
c'est une garantie de traçabilité (lacune S9 de l'audit).

---

## 5. Plan de sauvegarde et de restauration

### 5.1 Ce qui est sauvegardé

| Élément | Motif |
|---|---|
| Artefacts de build (JAR, bundle) | Rejouer une version sans la reconstruire |
| Charts Helm et values | Reproduire un déploiement à l'identique |
| Code Terraform et playbooks Ansible | Reconstruire l'infrastructure |
| Configuration ELK | Retrouver tableaux de bord et alertes |
| Définition du pipeline | Reconstruire la chaîne elle-même |
| Documentation | Conserver les décisions et leurs motifs |

### 5.2 Ce qui n'est jamais sauvegardé

Les chemins sensibles sont **exclus explicitement** de l'archive : `.env`, `*.key`, `*.pem`,
`*.p12`, `kubeconfig`, `secrets.yaml`, `*.tfstate`, ainsi que `node_modules` et `.git`.

Une archive de sauvegarde est un fichier qui circule, se copie et se stocke ailleurs. Y inclure un
credential reviendrait à le diffuser.

### 5.3 Garanties d'intégrité

Chaque sauvegarde produit trois fichiers :

| Fichier | Rôle |
|---|---|
| `microcrm_<horodatage>.tar.gz` | L'archive |
| `.sha256` | Empreinte, vérifiée **avant** toute restauration |
| `.json` | Manifeste : contenu, commit, branche, taille, machine |

L'archive est **relue intégralement juste après sa création**. Une archive corrompue est ainsi
détectée à la création, et non le jour où l'on en a besoin.

L'horodatage est en **UTC** : les archives produites sur des machines de fuseaux différents restent
triables, et un changement d'heure ne crée pas deux archives de même nom.

### 5.4 Rétention

Sept archives sont conservées par défaut. La décision de purge est isolée dans une **fonction pure**,
séparée de son exécution, et couverte par des tests unitaires portant sur les cas limites :

| Cas limite testé | Comportement exigé |
|---|---|
| Rétention à zéro | Ne supprime rien |
| Rétention négative ou non numérique | Ne supprime rien |
| Nombre d'archives égal à la rétention | Ne supprime rien |
| Ordre d'entrée quelconque | Résultat identique |

Un défaut à cet endroit détruirait des sauvegardes : les tests portent donc sur les cas qui
détruisent des données, pas sur le cas nominal.

### 5.5 La restauration est testée à chaque exécution du pipeline

> **Une sauvegarde qui n'a jamais été restaurée n'est pas une sauvegarde : c'est une hypothèse.**

Le pipeline exécute à chaque fois le cycle complet : sauvegarde, vérification de l'empreinte et du
manifeste, restauration dans un répertoire temporaire, puis **comparaison du contenu restauré à la
source** par `diff -r`. Si le contenu diffère, le pipeline échoue.

### 5.6 Restauration en situation réelle

```
./scripts/backup.sh --mode restauration \
    --archive backups/microcrm_20260818-020000.tar.gz \
    --cible /chemin/de/restauration
```

L'empreinte est vérifiée **avant** toute écriture. Une archive altérée est refusée, et le répertoire
cible n'est jamais écrasé sans `--forcer`.

### 5.7 Limite majeure, assumée

L'application utilise **HSQLDB en mémoire**. Il n'y a donc, à ce jour, **aucune donnée applicative à
sauvegarder** : tout disparaît au redémarrage du pod, quelle que soit la procédure.

Le plan couvre les artefacts et les configurations, ce qui permet de reconstruire l'environnement.
Il ne couvre pas les données, parce qu'il n'y en a pas de persistantes. C'est la **recommandation
n°1** du rapport de performance : migrer vers PostgreSQL, ce qui rendra la sauvegarde de données
nécessaire — et le gabarit de volume persistant est déjà en place dans le chart Helm, désactivé.

---

## 6. Procédures d'exploitation

### 6.1 Déployer une version

```
helm upgrade --install microcrm helm/microcrm \
    --namespace orion-dev \
    --values helm/microcrm/values-dev.yaml \
    --set image.tag=1.3.0 \
    --wait --timeout 300s
```

Ou, en passant par Ansible :

```
ansible-playbook ansible/deploiement.yml -e version=1.3.0 -e environnement=dev
```

### 6.2 Revenir à la version précédente

```
./scripts/rollback.sh --release microcrm --namespace orion-dev
```

### 6.3 Sauvegarder puis vérifier la restauration

```
ansible-playbook ansible/sauvegarde.yml -e retention=7
```

### 6.4 Que faire en cas d'échec de déploiement

| Symptôme | Cause probable | Action |
|---|---|---|
| Le Job de migration échoue | Artefact corrompu, base injoignable | Aucun pod n'a bougé : corriger, puis relancer |
| Les pods ne deviennent pas prêts | Régression applicative | `./scripts/rollback.sh` |
| Le service répond en erreur après déploiement | Régression fonctionnelle | `./scripts/rollback.sh` |
| `ImagePullBackOff` | Tag inexistant ou registre inaccessible | Vérifier le tag ; le chart interdit un tag implicite |

---

## 7. Ce qui reste à faire

| Priorité | Action | Prérequis |
|---|---|---|
| 1 | Sauvegarde des **données** applicatives | Migration vers PostgreSQL |
| 2 | Déploiement automatique vers staging à chaque release | Environnement staging permanent |
| 3 | Déploiement en production avec approbation explicite | Environnement de production |
| 4 | Externalisation des archives hors du poste | Stockage objet, S3 ou équivalent |
| 5 | Exercice de reprise complet, chronométré | Les points 1 et 4 |

Le point 4 mérite d'être souligné : une sauvegarde stockée sur la machine qu'elle protège ne protège
de rien. C'est une limite connue de l'implémentation locale actuelle, levée par le passage au cloud
décrit dans [`09-evolution-cloud.md`](09-evolution-cloud.md).

---

## Documents liés

| Document | Contenu |
|---|---|
| [`06-architecture.md`](06-architecture.md) | Schémas de la chaîne, de l'infrastructure et de la cible cloud |
| [`docs/captures/rollback/`](captures/rollback/) | Preuves d'exécution du rollback et des migrations |
| [`09-evolution-cloud.md`](09-evolution-cloud.md) | Migration vers le cloud |
