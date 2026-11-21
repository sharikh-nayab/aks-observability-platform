locals {
  name_prefix = "${var.project}-${var.environment}"
  tags        = merge(var.tags, { environment = var.environment })
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "./modules/network"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = var.vnet_cidr
  aks_subnet_cidr     = var.aks_subnet_cidr
  tags                = local.tags
}

# Container insights + control plane diagnostics land here. Dynatrace and
# Prometheus do the day-to-day work; this is the audit trail and the fallback
# when the in-cluster stack itself is what's broken.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.name_prefix}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

module "aks" {
  source = "./modules/aks"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.network.aks_subnet_id

  kubernetes_version = var.kubernetes_version
  sku_tier           = var.sku_tier
  availability_zones = var.availability_zones

  system_node_size  = var.system_node_size
  system_node_count = var.system_node_count
  user_node_size    = var.user_node_size
  user_node_min     = var.user_node_min
  user_node_max     = var.user_node_max

  pod_cidr       = var.pod_cidr
  service_cidr   = var.service_cidr
  dns_service_ip = var.dns_service_ip

  admin_group_object_ids     = var.admin_group_object_ids
  authorized_ip_ranges       = var.authorized_ip_ranges
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "control-plane-to-law"
  target_resource_id         = module.aks.cluster_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # kube-apiserver and controller-manager are noisy and expensive; audit +
  # autoscaler is what I've actually needed during incidents.
  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }
}
