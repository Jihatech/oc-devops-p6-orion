# Preuves — durcissement des images de conteneurs

> Comparaison **avant / après** du travail de conteneurisation de la phase 4.
> Les rapports Trivy bruts sont versionnés à côté (`trivy-back.json`, `trivy-front.json`).

## Point de départ : le Dockerfile fourni

L'application était livrée avec **un seul Dockerfile multi-étages** produisant trois cibles
(`front`, `back`, `standalone`). L'audit y avait relevé six défauts (constats A5 à A10) :

| Constat | Défaut |
|---|---|
| A5 | `EXPOSE 4200` dans l'étage `back`, alors que Spring Boot écoute sur **8080** |
| A6 | L'étage `standalone` copiait **deux systèmes de fichiers entiers** (`COPY --from=front / /`) |
| A7 | Les quatre étages s'exécutaient en **root** |
| A8 | Bases non épinglées (`node`, `gradle:jdk17`, `alpine:3.19`) et paquets installés sans version (`apk add caddy`) |
| A9 | Compilation en JDK **17**, exécution en JDK **21** |
| A10 | Aucun `HEALTHCHECK` |

## Ce qui a été fait

Le Dockerfile unique est remplacé par **un Dockerfile multi-étages par composant** —
`app/back/Dockerfile` et `app/front/Dockerfile` —, chacun séparant strictement l'étage de
construction (outils, sources) de l'étage d'exécution (artefact seul).

L'étage `standalone` n'est **pas reconduit** : faire cohabiter deux services dans un conteneur
piloté par supervisord contredit l'orchestration Kubernetes, qui gère les composants comme des
déploiements distincts, dimensionnés et redémarrés indépendamment.

| Constat | Correction |
|---|---|
| A5 | `EXPOSE 8080` — le port réellement écouté |
| A6 | Étage `standalone` supprimé |
| A7 | `USER` non privilégié : UID **10001** (backend), UID **101** (frontend, nginx-unprivileged) |
| A8 | **Toutes** les bases épinglées **par digest** — un tag peut être republié, un digest non |
| A9 | JDK 17 à la construction **et** à l'exécution |
| A10 | `HEALTHCHECK` applicatif sur les deux images |

## Résultats mesurés

### Vulnérabilités des images (Trivy, HIGH/CRITICAL corrigibles)

| Image | Dockerfile fourni | Après réécriture | Après correctifs Alpine | Écart total |
|---|---|---|---|---|
| **backend** | 31 | 3 | **0** | **−100 %** |
| **frontend** | 55 (base Caddy) | 10 | **0** | **−100 %** |

Les trois étapes correspondent à trois décisions distinctes : réécriture des Dockerfiles et montée
de Spring Boot, changement de serveur web, puis application des correctifs système.

### Taille des images

| Image | Taille |
|---|---|
| backend | 360 Mo (JRE 17 + JAR Spring Boot de 48 Mo) |
| frontend | 82 Mo |

## Les deux décisions qui expliquent ces chiffres

### 1. Spring Boot 3.2.5 → 3.5.16 (backend)

Le scan de l'image initiale remontait **31 paquets vulnérables** : `spring-webmvc`
(traversée de chemin), `tomcat-embed-core`, `jackson-databind`, `spring-expression`…

Contrairement au cas Angular (voir `.trivyignore.yaml`), les correctifs existaient **dans la même
version majeure** : il s'agissait d'une montée **mineure**, au risque de régression bien plus
faible. Elle a été appliquée et **vérifiée par la suite de tests**, qui reste verte.

**Les 3 vulnérabilités restantes** étaient des paquets du système de base (`libexpat`, `p11-kit`,
`p11-kit-trust`), dont le correctif existait dans les dépôts Alpine mais pas encore dans l'image
publiée en amont. Elles ont été traitées par la troisième décision, ci-dessous.

### 2. Caddy → nginx-unprivileged (frontend)

Le Dockerfile d'origine installait Caddy par `apk add`. À configuration fonctionnelle équivalente,
l'analyse des deux images officielles donne :

| Image | CVE HIGH/CRITICAL corrigibles |
|---|---|
| `caddy:2.11.2-alpine` | **55** |
| `nginxinc/nginx-unprivileged:1.29-alpine` | **10** |

**47 des 55** proviennent du binaire Go de Caddy, compilé avec une bibliothèque standard en
retard (`stdlib`, `golang.org/x/crypto`, `golang.org/x/net`). nginx, écrit en C, n'expose pas
cette surface. La variante *unprivileged* écoute nativement sur 8080 en utilisateur non
privilégié : elle satisfait A7 sans contorsion.

> **Ce que cette décision illustre** : le scan d'image ne sert pas seulement à bloquer une
> livraison. Il a orienté ici un **choix d'architecture** — et l'a orienté sur une mesure, pas sur
> une préférence.

### 3. Application des correctifs système (`apk --no-cache upgrade`)

Après les deux décisions précédentes, il restait **3 CVE côté backend** et **10 côté frontend** —
toutes des paquets du système de base (`libexpat`, `p11-kit`, `libcrypto3`, `libssl3`, `curl`,
`c-ares`, `libxml2`). Leur correctif existait **déjà dans les dépôts Alpine**, mais pas encore dans
les images de base publiées.

Deux réponses possibles :

| Option | Effet | Retenue |
|---|---|---|
| Accepter les 13 CVE dans `.trivyignore.yaml` | L'image reste vulnérable en attendant une reconstruction en amont, sur laquelle Orion n'a aucune prise | ❌ |
| **Appliquer les correctifs à la construction** | Les 13 CVE disparaissent réellement | ✅ |

**Compromis assumé** : la base reste épinglée par digest — le point de départ est déterministe —,
mais les paquets corrigés sont tirés au moment de la construction. Deux constructions éloignées
dans le temps peuvent donc différer d'un niveau de correctif.

C'est le bon arbitrage : sans cette instruction, l'image traîne les CVE système du jour où l'image
de base a été publiée. La traçabilité est préservée autrement — le scan Trivy de chaque image
publiée est archivé, et le re-scan hebdomadaire détecte toute dérive ultérieure.

**Résultat : 0 vulnérabilité HIGH/CRITICAL corrigible sur les deux images.** La porte de sécurité
du pipeline peut donc rester stricte, sans aucune exception.

## Correction connexe : l'URL de l'API

Le frontend appelait `http://localhost:8080` **en dur** (`app/front/src/app/config.ts`). Ce choix
fonctionne sur un poste de développement mais rend l'application **indéployable** : le navigateur
de l'utilisateur résoudrait `localhost` vers sa propre machine.

L'URL est devenue **relative** (`/api`), et nginx relaie `/api/*` vers le backend, dont l'adresse
est injectée par la variable `BACKEND_URL`. La **même image** fonctionne ainsi en local, sur
Minikube et sur un cluster managé, sans reconstruction.

Un fichier `app/front/proxy.conf.json` reproduit ce relais pour `ng serve`, afin que le
développement local se comporte comme la production.

## Vérification effectuée

```
docker run -d --name mc-back  -p 18080:8080 orion-microcrm-back:v2
docker run -d --name mc-front -p 18081:8080 -e BACKEND_URL=http://mc-back:8080 orion-microcrm-front:v3
```

| Contrôle | Résultat |
|---|---|
| Utilisateur backend | `uid=10001(orion)` — non-root ✅ |
| Utilisateur frontend | `uid=101(nginx)` — non-root ✅ |
| `HEALTHCHECK` | `healthy` sur les deux conteneurs ✅ |
| `/healthz` | 200 ✅ |
| `/` (SPA) | 200 ✅ |
| `/persons/1` (route SPA profonde) | 200 ✅ — `try_files` opérant |
| `/api/persons` (relais) | 200, **données réelles renvoyées** ✅ |
