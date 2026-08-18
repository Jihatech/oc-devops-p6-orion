# =============================================================================
# Sorties — consommées par les playbooks Ansible et par les scripts
# =============================================================================

output "namespaces" {
  description = "Namespaces provisionnés, par environnement."
  value       = { for cle, mod in module.environnements : cle => mod.nom }
}

output "commandes_utiles" {
  description = "Commandes de vérification, affichées après un apply."
  value = join("\n", [
    for cle, mod in module.environnements :
    "kubectl get resourcequota,limitrange,networkpolicy -n ${mod.nom}"
  ])
}
