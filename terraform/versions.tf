# =============================================================================
# Versions et fournisseurs — infrastructure locale Orion
# =============================================================================
#
# Toutes les versions sont contraintes explicitement. Un fournisseur non
# épinglé se met à jour silencieusement et peut modifier le plan sans qu'aucun
# code n'ait changé — exactement le défaut de reproductibilité reproché au
# pipeline d'origine (constat C4 de l'audit, principe P5).
# =============================================================================

terraform {
  required_version = "~> 1.15"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

# Le fournisseur lit le kubeconfig local. Le fichier n'est JAMAIS versionné
# (voir .gitignore) : il contient les credentials d'accès au cluster.
provider "kubernetes" {
  config_path    = var.chemin_kubeconfig
  config_context = var.contexte_kubernetes
}
