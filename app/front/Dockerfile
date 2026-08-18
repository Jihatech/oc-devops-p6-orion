# =============================================================================
# Image du composant FRONTEND — MicroCRM (Angular 17 servi par nginx)
# =============================================================================
#
# BUT
#   Produire une image de production minimale, reproductible et non
#   privilégiée servant le bundle Angular compilé, et relayant /api vers le
#   backend. Remplace l'étage `front` du Dockerfile fourni.
#
# CORRECTIONS APPORTÉES (référence : docs/01-audit-swot.md)
#   A7  exécution en root -> image nginx-unprivileged, non-root par conception
#   A8  `node` et `alpine` non épinglés, `apk add caddy` sans version
#                                     -> images épinglées PAR DIGEST
#   A10 aucune sonde                  -> HEALTHCHECK sur un point /healthz dédié
#
# CHOIX DU SERVEUR : nginx plutôt que Caddy
#   Le Dockerfile d'origine installait Caddy. À configuration équivalente,
#   l'analyse Trivy des deux images officielles donne :
#     caddy:2.11.2-alpine                     55 CVE HIGH/CRITICAL corrigibles
#     nginxinc/nginx-unprivileged:1.29-alpine 10 CVE HIGH/CRITICAL corrigibles
#   L'écart vient du binaire Go de Caddy, compilé avec une bibliothèque
#   standard en retard (47 des 55 CVE). nginx, écrit en C, n'expose pas cette
#   surface. La variante « unprivileged » écoute nativement sur 8080 en
#   utilisateur non privilégié : elle satisfait A7 sans contorsion.
#
# CONSTRUCTION
#   Contexte attendu : le répertoire `app/`
#     docker build -f app/front/Dockerfile -t orion-microcrm-front:<tag> app/
# =============================================================================

# --- Étage 1 : construction -------------------------------------------------
FROM node:20.19.5-alpine@sha256:be8d32d651b3e0c9c2b28fdc1d3888408125d703232013cff955344d052027e5 AS build

WORKDIR /src

# Verrou copié seul d'abord : la couche d'installation n'est rejouée que si le
# verrou change, pas à chaque modification de source.
COPY front/package.json front/package-lock.json ./
# `npm ci` et non `npm install` : installe exactement les versions figées.
RUN npm ci --no-audit --no-fund

COPY front/ ./
RUN npx ng build --configuration production

# --- Étage 2 : exécution ----------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.29-alpine@sha256:8059701048a6cc7d64e8ab2812a44be70161bfa9ecfc01d69e95b8ff2a648705 AS runtime

# L'image applique la substitution de variables aux fichiers de ce répertoire
# au démarrage. Le filtre restreint la substitution à BACKEND_URL, afin de ne
# pas altérer les variables internes de nginx ($uri, $host…).
COPY --chown=101:101 misc/docker/nginx.conf.template /etc/nginx/templates/default.conf.template
ENV NGINX_ENVSUBST_FILTER=BACKEND_URL
ENV BACKEND_URL=http://microcrm-back:8080

COPY --from=build --chown=101:101 /src/dist/microcrm/browser/ /usr/share/nginx/html/

# UID 101 : celui de l'image nginx-unprivileged. Il est déclaré explicitement
# pour correspondre au securityContext des manifestes Helm — une image
# non-root déployée avec un securityContext incohérent ne démarre pas.
USER 101:101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/healthz || exit 1
