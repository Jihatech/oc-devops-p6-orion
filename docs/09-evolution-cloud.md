# 09 — Plan d'évolution vers le cloud

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Objet** : décrire concrètement le passage de l'infrastructure locale (Minikube) à une
> infrastructure cloud managée : architecture cible, ce qui change dans la chaîne, coûts estimés,
> étapes de bascule.
>
> **Accessibilité** : structure hiérarchisée, tableaux simples, description textuelle des schémas.

---

## Sommaire

1. [Pourquoi le local d'abord](#1-pourquoi-le-local-dabord)
2. [Architecture cible](#2-architecture-cible)
3. [Ce qui change réellement](#3-ce-qui-change-réellement)
4. [Ce qui ne change pas](#4-ce-qui-ne-change-pas)
5. [Estimation des coûts](#5-estimation-des-coûts)
6. [Étapes de bascule](#6-étapes-de-bascule)
7. [Risques et points de vigilance](#7-risques-et-points-de-vigilance)
8. [Alternative multi-cloud](#8-alternative-multi-cloud)

---

## 1. Pourquoi le local d'abord

Le choix de Minikube est **délibéré et documenté**, pas un repli par défaut.

| Critère | Minikube | Cluster managé |
|---|---|---|
| Coût mensuel | **0 €** | Environ 150 à 250 € |
| Ce qu'il démontre | Maîtrise de l'orchestration | La même chose, en payant |
| Reproductible par un tiers | **Oui, immédiatement** | Nécessite un compte et des droits |
| Pertinent pour une application hors production | Oui | Non |

L'application MicroCRM **n'est pas en production** : elle en est à son deuxième sprint et n'est
déployée que sur un environnement de démonstration. Engager 200 € par mois pour héberger une
application que personne n'utilise encore n'aurait rien démontré de plus.

Ce qui rend ce choix défendable, c'est que **la migration est préparée** : les manifestes sont
portables à 95 %, et ce document décrit précisément ce qu'il resterait à faire.

---

## 2. Architecture cible

L'architecture retenue est décrite en détail dans [`06-architecture.md`](06-architecture.md) §4, avec
son schéma et sa description textuelle. En voici la synthèse.

| Couche | Service AWS | Rôle |
|---|---|---|
| Entrée | Route 53, CloudFront | DNS, diffusion de contenu, terminaison TLS |
| Contenu statique | S3 | Bundle Angular, sauvegardes |
| Répartition | Application Load Balancer | Entrée applicative, terminaison TLS |
| Exécution | EKS, groupe de nœuds EC2 | Orchestration des conteneurs |
| Données | RDS PostgreSQL Multi-AZ | Base persistante et redondée |
| Secrets | Secrets Manager | Credentials, sans variable d'environnement |
| Images | ECR | Registre privé |
| Observabilité | CloudWatch Logs, OpenSearch | Journaux et tableaux de bord |
| Accès de la chaîne | OIDC et rôle IAM | Authentification **sans secret de longue durée** |

### Le point d'architecture le plus important

**L'authentification de la chaîne d'intégration passe par OIDC, pas par une clé d'accès.** GitHub
Actions obtient un jeton temporaire auprès d'AWS, valable le temps d'un job.

C'est la suppression d'une classe entière de risque : il n'existe plus de clé longue durée à
stocker, à faire tourner, ni à révoquer en urgence si elle fuite. C'est la même logique que celle
déjà appliquée localement, où le jeton de publication est régénéré à chaque exécution.

---

## 3. Ce qui change réellement

### 3.1 Dans la chaîne d'intégration

| Élément | Aujourd'hui | Après migration | Ampleur |
|---|---|---|---|
| Authentification au registre | Jeton natif de la plateforme | **OIDC et rôle IAM** | Un bloc de configuration |
| Registre d'images | GHCR | ECR | Une variable |
| Accès au cluster | Fichier de configuration local | OIDC, puis `aws eks update-kubeconfig` | Une étape supplémentaire |
| Déploiement | Manuel depuis le poste | Automatique vers la recette | Un job supplémentaire |
| Scan des images | Trivy dans la chaîne | Trivy **plus** scan natif du registre | Défense en profondeur |

### 3.2 Dans les valeurs de déploiement

| Paramètre | Aujourd'hui | Après migration |
|---|---|---|
| Registre | Vide, images locales | `<compte>.dkr.ecr.<région>.amazonaws.com` |
| Politique de récupération | `Never` | `IfNotPresent` |
| Classe de stockage | `standard` | `gp3` |
| Ingress | Désactivé | Activé, contrôleur AWS |
| Persistance | Désactivée | Activée |
| Secrets | Désactivés | Fournis par Secrets Manager |
| Répliques | 1 | 2 minimum, avec mise à l'échelle automatique |

**Toutes ces modifications tiennent dans un fichier de valeurs supplémentaire.** Les gabarits Helm
eux-mêmes ne changent pas.

### 3.3 Dans l'application

Un seul changement est réellement structurant : **la base de données**. Passer de HSQLDB en mémoire
à PostgreSQL est un changement applicatif, pas d'infrastructure.

C'est la **recommandation n°1** du rapport de performance, et elle est de toute façon indispensable
avant toute mise en production : aujourd'hui, un redémarrage de conteneur efface toutes les données.

### 3.4 Dans l'observabilité

| Aujourd'hui | Après migration |
|---|---|
| Elasticsearch sur le poste | OpenSearch managé |
| Filebeat en DaemonSet | Fluent Bit vers CloudWatch, puis OpenSearch |
| Sécurité désactivée | Chiffrement en transit et au repos, authentification |

Le **modèle de données ne change pas** : les tableaux de bord et les règles d'alerte sont
transposables, les mêmes champs étant indexés.

---

## 4. Ce qui ne change pas

C'est le point le plus important de ce document, et le meilleur argument en faveur du travail
réalisé localement.

| Élément | Portable tel quel |
|---|---|
| Les cinq étapes de la chaîne | Oui, intégralement |
| Les Dockerfiles | Oui, sans modification |
| Les gabarits Helm | Oui, seules les valeurs changent |
| Les scripts d'automatisation | Oui, ils pilotent des outils standards |
| L'analyse de qualité et les portes de qualité | Oui |
| Les contrôles de sécurité | Oui, avec une couche supplémentaire |
| La procédure de rollback | Oui, `helm rollback` est identique |
| Les migrations par composant | Oui, le mécanisme est le même |
| Le calcul des indicateurs DORA | Oui, il interroge la plateforme de code |
| La structure des tableaux de bord | Oui, mêmes champs indexés |

**Ce qui a été construit sur Minikube n'est pas un prototype jetable.** Le travail d'industrialisation
— ordre des étapes, portes de qualité, immuabilité des artefacts, réversibilité — est indépendant de
l'hébergement.

---

## 5. Estimation des coûts

### 5.1 Environnement de recette seul

| Service | Configuration | Coût mensuel estimé |
|---|---|---|
| EKS, plan de contrôle | 1 cluster | 73 € |
| EC2, nœuds | 2 instances t3.medium | 60 € |
| RDS PostgreSQL | db.t3.micro, mono-AZ | 15 € |
| Load Balancer | 1 ALB | 20 € |
| ECR | Moins de 10 Go | 1 € |
| S3 | Moins de 10 Go | 1 € |
| CloudWatch Logs | Moins de 5 Go par mois | 3 € |
| Transfert de données | Faible | 5 € |
| **Total** | | **environ 180 € par mois** |

### 5.2 Recette et production

| Service | Configuration | Coût mensuel estimé |
|---|---|---|
| EKS, plan de contrôle | 2 clusters | 146 € |
| EC2, nœuds | 2 plus 3 instances t3.medium | 150 € |
| RDS PostgreSQL | Micro en recette, small Multi-AZ en production | 75 € |
| Load Balancer | 2 ALB | 40 € |
| CloudFront | Moins de 100 Go | 10 € |
| OpenSearch | 1 nœud t3.small | 30 € |
| Autres | ECR, S3, CloudWatch, transfert | 20 € |
| **Total** | | **environ 470 € par mois** |

### 5.3 Leviers d'optimisation

| Levier | Économie estimée | Contrepartie |
|---|---|---|
| Instances réservées sur un an | 30 à 40 % sur EC2 et RDS | Engagement de durée |
| Instances ponctuelles pour la recette | Jusqu'à 70 % sur EC2 | Interruptions possibles |
| Un seul cluster, deux namespaces | 73 € par mois | Isolation moindre entre environnements |
| Extinction de la recette hors heures ouvrées | Environ 60 % sur les nœuds de recette | Indisponibilité programmée |
| Cycle de vie des journaux vers stockage froid | 50 à 70 % sur le stockage | Accès plus lent aux archives |

**Le levier le plus rentable est le dernier de la liste** : éteindre l'environnement de recette la
nuit et le week-end représente environ 128 heures d'inactivité sur 168, sans aucune contrepartie
réelle — personne n'y travaille pendant ces créneaux.

---

## 6. Étapes de bascule

### Étape 1 — Préparer l'application

| Action | Livrable |
|---|---|
| Migrer vers PostgreSQL | Profil applicatif, tests avec base réelle |
| Ajouter l'authentification à l'interface de programmation | Traitement du risque critique |
| Externaliser la configuration | Aucune valeur d'environnement en dur |

**Cette étape est un prérequis absolu.** Migrer vers le cloud une application dont la base est en
mémoire ne ferait que déplacer le problème en le rendant plus coûteux.

### Étape 2 — Provisionner l'infrastructure

| Action | Livrable |
|---|---|
| Étendre le code d'infrastructure au fournisseur AWS | Modules réseau, cluster, base |
| Configurer l'état distant et son verrouillage | Travail à plusieurs sans conflit |
| Créer le rôle et la relation de confiance OIDC | Accès sans secret de longue durée |

Le code d'infrastructure existant est structuré en modules : l'ajout d'un fournisseur ne remet pas
en cause l'organisation.

### Étape 3 — Adapter la chaîne

| Action | Livrable |
|---|---|
| Remplacer l'authentification au registre par OIDC | Aucun secret de longue durée |
| Publier sur ECR | Une variable modifiée |
| Ajouter le déploiement automatique vers la recette | Un job supplémentaire |

### Étape 4 — Basculer l'observabilité

| Action | Livrable |
|---|---|
| Déployer la collecte de journaux vers CloudWatch | Journaux centralisés |
| Recréer les tableaux de bord sur OpenSearch | Mêmes champs, import des objets |
| Recréer les règles d'alerte, avec canal de notification | Alertes reçues, pas seulement levées |

### Étape 5 — Valider

| Action | Critère de réussite |
|---|---|
| Déployer en recette | Application accessible, sondes vertes |
| **Rejouer la démonstration de rollback** | Retour arrière vérifié sur le cluster managé |
| Exécuter un test de charge | Comportement connu sous charge |
| Vérifier sauvegarde et restauration | Restauration effectuée sur données réelles |

**L'étape la plus importante est le rejeu du rollback.** Une procédure qui fonctionne localement doit
être re-vérifiée sur l'infrastructure cible : c'est là qu'on découvre les écarts, notamment les
politiques réseau, que Minikube n'applique pas.

### Étape 6 — Mettre en production

| Action | Précaution |
|---|---|
| Déployer en production | Approbation manuelle explicite |
| Activer la mise à l'échelle automatique | Bornes basse et haute définies |
| Activer les sauvegardes automatiques | Restauration testée avant l'ouverture du service |

---

## 7. Risques et points de vigilance

| Risque | Probabilité | Impact | Mesure |
|---|---|---|---|
| **Dérive des coûts** | Élevée | Élevé | Budgets et alertes de dépassement dès le premier jour |
| Politiques réseau non testées localement | **Certaine** | Moyen | Minikube ne les applique pas : les valider dès la recette |
| Migration de base plus longue que prévu | Moyenne | Élevé | Traiter cette étape en premier et isolément |
| Dépendance à un fournisseur unique | Moyenne | Moyen | Kubernetes et Helm restent portables, voir §8 |
| Compétences cloud à acquérir | Élevée | Moyen | Deux personnes à l'exploitation : prévoir la formation |
| Secrets mal migrés | Faible | **Critique** | Secrets Manager dès le départ, jamais de valeur en dur |

### Le risque le plus sous-estimé

**La dérive des coûts.** Un cluster managé facture à l'heure, y compris la nuit et le week-end. Sans
budget ni alerte, la facture du premier mois est systématiquement une surprise.

La mesure est simple et doit être prise **avant** la première ressource créée, pas après la première
facture.

---

## 8. Alternative multi-cloud

Le guide mentor mentionne l'adaptation à une architecture multi-cloud ou hybride comme question
d'approfondissement.

### 8.1 Ce qui est déjà portable

| Élément | Portabilité |
|---|---|
| Images de conteneurs | Totale, format standard |
| Gabarits Helm | Totale |
| Chaîne d'intégration | Élevée, les étapes sont indépendantes du fournisseur |
| Code d'infrastructure | Moyenne, les modules changent selon le fournisseur |

### 8.2 Correspondance entre fournisseurs

| Fonction | AWS | Azure | GCP |
|---|---|---|---|
| Orchestration | EKS | AKS | GKE |
| Registre d'images | ECR | ACR | Artifact Registry |
| Base relationnelle | RDS | Database for PostgreSQL | Cloud SQL |
| Stockage objet | S3 | Blob Storage | Cloud Storage |
| Secrets | Secrets Manager | Key Vault | Secret Manager |
| Journaux | CloudWatch | Monitor | Cloud Logging |

### 8.3 Recommandation

**Ne pas viser le multi-cloud pour une équipe de deux personnes à l'exploitation.** Le coût de
maintien de deux infrastructures dépasse largement le bénéfice d'indépendance recherché.

La bonne posture est le **maintien de la portabilité** : s'appuyer sur Kubernetes et Helm — ce qui
est déjà le cas — et isoler les parties spécifiques au fournisseur dans des modules d'infrastructure
distincts. Un changement de fournisseur devient alors un projet de quelques semaines, et non une
réécriture.

C'est exactement ce que démontre le travail réalisé : la même chaîne, les mêmes charts et les mêmes
scripts fonctionnent aujourd'hui sur Minikube et fonctionneraient demain sur n'importe quel cluster
Kubernetes.

---

## Documents liés

| Document | Contenu |
|---|---|
| [`06-architecture.md`](06-architecture.md) | Schéma de l'architecture cloud cible et sa description |
| [`07-plan-releases-rollback-backup.md`](07-plan-releases-rollback-backup.md) | Procédures à rejouer sur la cible |
| [`08-rapport-performance-matiere.md`](08-rapport-performance-matiere.md) | Recommandations d'amélioration continue |
