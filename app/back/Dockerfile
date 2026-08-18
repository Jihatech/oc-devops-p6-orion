# =============================================================================
# Image du composant BACKEND — MicroCRM (Spring Boot 3 / Java 17)
# =============================================================================
#
# BUT
#   Produire une image de production minimale, reproductible et non
#   privilégiée pour l'API MicroCRM. Remplace l'étage `back` du Dockerfile
#   fourni, dont l'audit a relevé plusieurs défauts (constats A5 à A10).
#
# CORRECTIONS APPORTÉES (référence : docs/01-audit-swot.md)
#   A5  EXPOSE 4200 -> 8080           le port réellement écouté par Spring Boot
#   A7  exécution en root -> USER     utilisateur non privilégié dédié (UID 10001)
#   A8  bases non épinglées           -> images épinglées PAR DIGEST
#   A9  compilation 17 / exécution 21 -> JDK 17 des deux côtés
#   A10 aucune sonde                  -> HEALTHCHECK applicatif
#
# CONSTRUCTION
#   Contexte attendu : le répertoire `app/`
#     docker build -f app/back/Dockerfile -t orion-microcrm-back:<tag> app/
# =============================================================================

# --- Étage 1 : construction -------------------------------------------------
# Épinglage PAR DIGEST : un tag, même précis comme « 8.7.0-jdk17-alpine », peut
# être republié sur un contenu différent. Le digest est le seul identifiant
# réellement immuable — c'est la réponse au constat A8 et à la menace M4
# (dérive silencieuse des images de base).
FROM gradle:8.7.0-jdk17-alpine@sha256:8112d34502ffa6b6b62c68fce801a0c32114199f258f1f69ffd8da2281547083 AS build

WORKDIR /src

# Les descripteurs de build sont copiés avant les sources : tant qu'ils ne
# changent pas, la couche de résolution des dépendances reste en cache.
COPY back/gradle/ gradle/
COPY back/gradlew back/settings.gradle back/build.gradle ./
RUN chmod +x gradlew \
    && ./gradlew dependencies --configuration runtimeClasspath --no-daemon --console=plain -q

COPY back/src/ src/
# bootJar seul : les tests sont exécutés par le pipeline, pas au moment de la
# construction de l'image. Les rejouer ici doublerait le temps de build sans
# rien apporter — et masquerait un échec de test derrière un échec de build.
RUN ./gradlew bootJar --no-daemon --console=plain \
    && cp build/libs/*.jar /tmp/application.jar

# --- Étage 2 : exécution ----------------------------------------------------
# JRE seul : ni compilateur, ni Gradle, ni sources dans l'image livrée.
FROM eclipse-temurin:17.0.19_10-jre-alpine-3.23@sha256:b658bee7bbf0277559bd07dfb2e8473c30dc90c3da0d8cfe568e61f52792ce52 AS runtime

# Utilisateur non privilégié (A7). L'UID est fixé explicitement pour
# correspondre au `securityContext.runAsUser` des manifestes Helm : une image
# non-root déployée avec un securityContext incohérent ne démarre pas.
# Application des correctifs de sécurité disponibles dans les dépôts Alpine.
#
# Compromis assumé : la base reste épinglée par digest — le point de départ est
# donc déterministe —, mais cette instruction tire les paquets corrigés au
# moment de la construction. Deux constructions éloignées dans le temps peuvent
# ainsi différer d'un niveau de correctif.
#
# C'est délibéré, et c'est le bon arbitrage : sans cette ligne, l'image traîne
# les CVE système du jour où l'image de base a été publiée, jusqu'à ce que son
# éditeur la reconstruise — un délai sur lequel Orion n'a aucune prise. La
# traçabilité est préservée autrement : le scan Trivy de chaque image publiée
# est archivé, et le re-scan hebdomadaire détecte toute dérive ultérieure.
RUN apk --no-cache upgrade

RUN addgroup -g 10001 -S orion && adduser -u 10001 -S orion -G orion

WORKDIR /app
COPY --from=build --chown=10001:10001 /tmp/application.jar /app/application.jar

USER 10001:10001

# Port réellement écouté par Spring Boot. Le Dockerfile d'origine déclarait
# 4200 — le port du serveur de développement Angular (constat A5).
EXPOSE 8080

# La sonde interroge l'application, pas le processus : une JVM vivante ne
# signifie pas que l'API répond (constat A10). wget est fourni par busybox,
# donc aucun paquet supplémentaire n'est installé.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

# Forme exec, sans shell intermédiaire : les signaux d'arrêt parviennent
# directement à la JVM, ce qui permet un arrêt propre sous Kubernetes.
# MaxRAMPercentage rend la JVM sensible aux limites mémoire du conteneur.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/application.jar"]
