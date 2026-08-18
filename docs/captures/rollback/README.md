# Preuves — déploiement, échec et rollback

> Démonstration **exécutée réellement** sur Minikube le 18/08/2026, journalisée dans
> [`demonstration.log`](demonstration.log) et [`trace-rollback.log`](trace-rollback.log).
> Répond à la faiblesse **f8** de l'audit (aucune procédure de retour arrière chez Orion) et à la
> question de soutenance annoncée par le guide mentor : *« en cas d'échec de déploiement, quelle
> procédure de rollback et comment l'avez-vous automatisée ? »*.

## Le scénario, et pourquoi celui-là

| Étape | Action | Résultat |
|---|---|---|
| 1 | `helm install` de la version **1.0.0** | ✅ 2 pods prêts, service fonctionnel |
| 2 | `helm upgrade` vers la version **1.1.0**, porteuse d'une régression | ❌ Échec après 120 s |
| 3 | Constat de l'état pendant l'échec | Pod 1.1.0 **non prêt**, pod 1.0.0 **toujours prêt** |
| 4 | Contrôle de disponibilité | **200 sur toutes les requêtes — aucune interruption** |
| 5 | `./scripts/rollback.sh` | ✅ Révision 1 restaurée et **vérifiée en 18 s** |
| 6 | État final | 1.0.0 en service, historique Helm complet |

**La régression simulée est une corruption de l'artefact** ([`Dockerfile.regression`](Dockerfile.regression)) :
le fichier `application.jar` est remplacé par du texte, et la JVM refuse de démarrer
(`Error: Invalid or corrupt jarfile`).

Ce cas a été préféré à un simple mauvais tag d'image (`ImagePullBackOff`) parce qu'il est **plus
proche d'un incident réel** : l'image existe, elle est tirée avec succès, le conteneur démarre — et
c'est l'**application** qui échoue. C'est exactement le scénario que les sondes doivent détecter, et
qu'un contrôle limité à « l'image se télécharge-t-elle ? » laisserait passer.

## Le résultat le plus important : aucune interruption de service

```
microcrm-back-76d7bf8c99-x8lmr    false   Running   orion-microcrm-back:1.1.0   <- nouvelle version, JAMAIS prête
microcrm-back-c776cdcc9-5pftr     true    Running   orion-microcrm-back:1.0.0   <- ancienne version, toujours en service
```

```
requête 1 -> /healthz=200  /api/persons=200
requête 2 -> /healthz=200  /api/persons=200
requête 3 -> /healthz=200  /api/persons=200
```

Le déploiement a échoué **sans que le service soit interrompu une seule seconde**. Deux mécanismes
combinés produisent ce résultat, et c'est leur conjonction qui compte :

1. **`maxUnavailable: 0`** dans la stratégie `RollingUpdate` — Kubernetes n'a le droit de retirer un
   ancien pod qu'après qu'un nouveau soit devenu prêt. Ici, aucun ne l'est jamais devenu : aucun
   ancien pod n'a donc été retiré.
2. **`startupProbe` et `readinessProbe`** — le pod défaillant n'a jamais été déclaré prêt, il n'a
   donc **jamais été inscrit dans le Service** et n'a jamais reçu la moindre requête utilisateur.

> Sans sondes, Kubernetes aurait considéré le conteneur comme sain du seul fait que son processus
> tournait — et aurait basculé le trafic vers une application incapable de répondre. **Les sondes ne
> sont pas un détail de configuration : elles sont ce qui rend le déploiement progressif sûr.**

## Le rollback

```bash
./scripts/rollback.sh --release microcrm --namespace orion-dev \
    --preuves docs/captures/rollback/trace-rollback.log
```

Le script ne se contente pas d'appeler `helm rollback` :

| Étape | Ce que fait le script | Pourquoi |
|---|---|---|
| 1 | Affiche l'historique et l'état des pods | Trace de la situation de départ |
| 2 | **Déduit la dernière révision SAINE** | Revenir sur une révision `failed` restaurerait une version déjà cassée |
| 3 | `helm rollback --wait` | Attend que les pods restaurés soient réellement prêts |
| 4 | Réaffiche l'état des pods et l'historique | Trace de l'effet obtenu |
| 5 | **Test de fumée HTTP** (frontend + API) | Une release marquée `deployed` dont le service ne répond pas **n'est pas** un rollback réussi |
| 6 | Écrit une trace horodatée | Preuve d'exécution, auditable |

Résultat mesuré : **18 secondes**, du lancement à la vérification du service.

### L'historique Helm reste complet

```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         failed      Upgrade "microcrm" failed: ... not ready ...
3         deployed    Rollback to 1
```

Un rollback Helm **ne supprime rien** : il crée une **nouvelle révision** dont le contenu est celui
de la révision cible. L'échec reste visible en révision 2. C'est un point de traçabilité important
(lacune **S9** de l'audit) : l'incident est conservé, daté et consultable — on ne peut pas effacer
un mauvais déploiement de l'historique.

## Deux modes de rollback, deux usages

| Mode | Commande | Usage |
|---|---|---|
| **Automatique** | `helm upgrade --atomic --timeout 5m` | Déploiement **non surveillé** (CI vers staging) : Helm revient seul à l'état antérieur en cas d'échec |
| **Piloté** | `./scripts/rollback.sh` | Incident **constaté après coup** (régression fonctionnelle, alerte) : l'opérateur décide, et obtient une trace vérifiée |

Le mode `--atomic` n'a délibérément **pas** été utilisé dans cette démonstration : il aurait masqué
l'état intermédiaire, qui est précisément ce qu'il fallait montrer — un déploiement en échec, un
service toujours disponible, et le choix explicite de revenir en arrière.

## Reproduire la démonstration

```bash
# 1. Cluster et images (dans le démon Docker de Minikube)
minikube start --driver=docker --cpus=2 --memory=3g
eval $(minikube -p minikube docker-env --shell bash)
docker build -f app/back/Dockerfile  -t orion-microcrm-back:1.0.0  app/
docker build -f app/front/Dockerfile -t orion-microcrm-front:1.0.0 app/

# 2. Déploiement initial
kubectl create namespace orion-dev
helm upgrade --install microcrm helm/microcrm -n orion-dev \
    -f helm/microcrm/values-dev.yaml --set image.tag=1.0.0 --wait

# 3. Version défectueuse
docker build -f docs/captures/rollback/Dockerfile.regression -t orion-microcrm-back:1.1.0 .
docker tag orion-microcrm-front:1.0.0 orion-microcrm-front:1.1.0
helm upgrade microcrm helm/microcrm -n orion-dev \
    -f helm/microcrm/values-dev.yaml --set image.tag=1.1.0 --wait --timeout 120s   # échoue

# 4. Rollback vérifié
./scripts/rollback.sh --release microcrm --namespace orion-dev
```
