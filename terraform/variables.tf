# =============================================================================
# Variables d'entrée
# =============================================================================

variable "chemin_kubeconfig" {
  description = "Chemin du fichier kubeconfig. Jamais versionné : il porte les credentials du cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "contexte_kubernetes" {
  description = "Contexte kubectl visé. Nommer le contexte explicitement évite d'appliquer un plan au mauvais cluster."
  type        = string
  default     = "minikube"
}

variable "environnements" {
  description = <<-DESC
    Environnements à provisionner, avec leurs quotas.

    Les quotas ne sont pas décoratifs : sans eux, un déploiement mal
    dimensionné consomme toute la capacité du cluster et met en défaut les
    autres environnements. Sur un Minikube de 3 Go, la contrainte est réelle.
  DESC

  type = map(object({
    quota_cpu_requests     = string
    quota_memoire_requests = string
    quota_cpu_limites      = string
    quota_memoire_limites  = string
    pods_max               = number
  }))

  default = {
    dev = {
      quota_cpu_requests     = "1"
      quota_memoire_requests = "1Gi"
      quota_cpu_limites      = "2"
      quota_memoire_limites  = "2Gi"
      pods_max               = 10
    }
    staging = {
      quota_cpu_requests     = "1"
      quota_memoire_requests = "1500Mi"
      quota_cpu_limites      = "2"
      quota_memoire_limites  = "3Gi"
      pods_max               = 15
    }
  }
}

variable "prefixe_namespace" {
  description = "Préfixe des namespaces créés (résultat : <prefixe>-<environnement>)."
  type        = string
  default     = "orion"
}
