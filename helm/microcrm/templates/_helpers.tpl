{{/*
Fonctions partagées du chart MicroCRM.
Centraliser le nommage évite que deux gabarits divergent : un Service qui ne
retrouve plus « son » Deployment est une panne silencieuse, et difficile à
diagnostiquer.
*/}}

{{- define "microcrm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "microcrm.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Étiquettes communes, conformes aux recommandations Kubernetes. */}}
{{- define "microcrm.labels" -}}
app.kubernetes.io/name: {{ include "microcrm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: microcrm
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Référence complète d'une image.
Usage : {{ include "microcrm.image" (dict "root" $ "composant" .Values.back) }}

Le tag est OBLIGATOIRE, sans aucun repli. Un repli sur .Chart.AppVersion
serait pire qu'inutile : il désignerait un tag d'image qui n'a probablement
jamais été publié, et le déploiement échouerait en ImagePullBackOff — un
symptôme obscur, loin de sa cause. Le rendu échoue donc ici, avec le message
qui indique exactement quoi faire.

Cette contrainte répond à la faiblesse f4 de l'audit : sans tag explicite et
immuable, on ne sait pas quelle version tourne, et le rollback n'a pas de
cible fiable.
*/}}
{{- define "microcrm.image" -}}
{{- $tag := .root.Values.image.tag -}}
{{- if not $tag -}}
{{- fail "image.tag est obligatoire : fournissez --set image.tag=<sha-xxxxxxx ou semver>" -}}
{{- end -}}
{{- $registry := .root.Values.image.registry -}}
{{- $repository := .root.Values.image.repository -}}
{{- $nom := .composant.image.name -}}
{{- if and $registry $repository -}}
{{- printf "%s/%s/%s:%s" $registry $repository $nom $tag -}}
{{- else -}}
{{- printf "%s:%s" $nom $tag -}}
{{- end -}}
{{- end -}}
