output "nom" {
  description = "Nom du namespace créé."
  value       = kubernetes_namespace.environnement.metadata[0].name
}

output "environnement" {
  description = "Environnement logique associé."
  value       = var.environnement
}
