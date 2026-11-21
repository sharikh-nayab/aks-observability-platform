output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "node_resource_group" {
  value = module.aks.node_resource_group
}

output "oidc_issuer_url" {
  description = "Needed when federating workload identities (e.g. external-dns, cert-manager)."
  value       = module.aks.oidc_issuer_url
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "get_credentials" {
  value = "az aks get-credentials -g ${azurerm_resource_group.this.name} -n ${module.aks.cluster_name} --overwrite-existing"
}
