# =============================================================================
# Module « namespace applicatif »
# =============================================================================
#
# BUT
#   Provisionner un environnement applicatif complet et cloisonné : le
#   namespace, ses quotas, ses valeurs de ressources par défaut et sa politique
#   réseau. Un environnement se crée et se détruit d'un seul bloc.
#
# POURQUOI UN MODULE
#   Les environnements dev et staging doivent être IDENTIQUES en structure et
#   ne différer que par leurs quotas. Dupliquer les ressources ferait
#   inévitablement diverger les deux — et cette divergence ne se révélerait
#   qu'au moment d'un incident en recette.
# =============================================================================

resource "kubernetes_namespace" "environnement" {
  metadata {
    name = var.nom

    labels = {
      "app.kubernetes.io/part-of"    = "microcrm"
      "app.kubernetes.io/managed-by" = "terraform"
      "orion.io/environnement"       = var.environnement
    }
  }
}

# --- Quotas de ressources ----------------------------------------------------
# Sans quota, un déploiement mal dimensionné consomme toute la capacité du
# cluster et met en défaut les autres environnements. Sur un Minikube de 3 Go,
# la contrainte est immédiate et concrète.
resource "kubernetes_resource_quota" "quota" {
  metadata {
    name      = "quota-${var.environnement}"
    namespace = kubernetes_namespace.environnement.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota_cpu_requests
      "requests.memory" = var.quota_memoire_requests
      "limits.cpu"      = var.quota_cpu_limites
      "limits.memory"   = var.quota_memoire_limites
      "pods"            = var.pods_max
    }
  }
}

# --- Valeurs de ressources par défaut ---------------------------------------
# Un pod sans `requests` ni `limits` est ordonnancé au hasard et peut affamer
# ses voisins. Le LimitRange impose un plancher : même un manifeste incomplet
# se voit attribuer des valeurs raisonnables.
#
# Il joue aussi un rôle de garde-fou vis-à-vis du quota : sans valeurs par
# défaut, un pod sans `requests` serait REFUSÉ par le quota, avec un message
# d'erreur peu explicite.
resource "kubernetes_limit_range" "limites" {
  metadata {
    name      = "limites-defaut-${var.environnement}"
    namespace = kubernetes_namespace.environnement.metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }

      max = {
        cpu    = "1"
        memory = "1Gi"
      }
    }
  }
}

# --- Politique réseau --------------------------------------------------------
# Refus par défaut du trafic entrant venant d'AUTRES namespaces : les
# environnements dev et staging ne doivent pas pouvoir se joindre. Le trafic
# interne au namespace reste autorisé, sans quoi le frontend ne pourrait plus
# joindre le backend.
#
# Note honnête : Minikube avec le pilote Docker n'applique pas les
# NetworkPolicy par défaut, faute de greffon réseau compatible (Calico ou
# Cilium). La ressource est néanmoins déclarée — elle est correcte, versionnée,
# et deviendra effective telle quelle sur un cluster managé. C'est justement le
# type d'écart qu'il vaut mieux documenter que découvrir en production.
resource "kubernetes_network_policy" "isolation" {
  metadata {
    name      = "isolation-${var.environnement}"
    namespace = kubernetes_namespace.environnement.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "orion.io/environnement" = var.environnement
          }
        }
      }
    }
  }
}
