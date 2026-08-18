# Entrées du module « namespace applicatif ».

variable "nom" {
  description = "Nom du namespace Kubernetes à créer."
  type        = string
}

variable "environnement" {
  description = "Environnement logique (dev, staging, prod) — porté en étiquette."
  type        = string
}

variable "quota_cpu_requests" {
  description = "Somme maximale des demandes CPU de tous les pods du namespace."
  type        = string
}

variable "quota_memoire_requests" {
  description = "Somme maximale des demandes mémoire de tous les pods du namespace."
  type        = string
}

variable "quota_cpu_limites" {
  description = "Somme maximale des limites CPU de tous les pods du namespace."
  type        = string
}

variable "quota_memoire_limites" {
  description = "Somme maximale des limites mémoire de tous les pods du namespace."
  type        = string
}

variable "pods_max" {
  description = "Nombre maximal de pods. Garde-fou contre une boucle de redémarrage qui saturerait le cluster."
  type        = number
}
