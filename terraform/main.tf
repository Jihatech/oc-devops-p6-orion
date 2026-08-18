# =============================================================================
# Infrastructure locale d'Orion — namespaces applicatifs
# =============================================================================
#
# RÉPARTITION DES RESPONSABILITÉS (docs/02-veille-recommandations.md §6)
#
#   Terraform  décrit CE QUI EXISTE : cycle de vie des ressources, état désiré,
#              destruction propre. Ici : namespaces, quotas, plages de limites,
#              politiques réseau.
#
#   Ansible    décrit CE QUI EST CONFIGURÉ DEDANS : prérequis machine,
#              démarrage du cluster, déploiement applicatif, sauvegarde.
#
# Cette frontière est explicite parce qu'elle est arbitraire si on ne la pose
# pas — et c'est une question de soutenance classique. La règle retenue :
# Terraform crée le contenant, Ansible agit sur le contenu.
#
# Les releases Helm ne sont volontairement PAS gérées par Terraform : elles
# changent à chaque livraison, plusieurs fois par jour. Les confier à
# Terraform ferait de chaque déploiement une modification d'infrastructure,
# et brouillerait la lecture de `terraform plan`.
# =============================================================================

module "environnements" {
  source = "./modules/namespace-applicatif"

  for_each = var.environnements

  nom                    = "${var.prefixe_namespace}-${each.key}"
  environnement          = each.key
  quota_cpu_requests     = each.value.quota_cpu_requests
  quota_memoire_requests = each.value.quota_memoire_requests
  quota_cpu_limites      = each.value.quota_cpu_limites
  quota_memoire_limites  = each.value.quota_memoire_limites
  pods_max               = each.value.pods_max
}
