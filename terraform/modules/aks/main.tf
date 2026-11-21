resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.name_prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  node_resource_group = "${var.name_prefix}-aks-nodes-rg"
  tags                = var.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = length(var.admin_group_object_ids) > 0
  azure_policy_enabled      = true

  # System pool only runs kube-system + the agents. Apps go to the user pool so
  # a runaway workload can't starve CoreDNS.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_size
    node_count                   = var.system_node_count
    vnet_subnet_id               = var.subnet_id
    zones                        = var.availability_zones
    only_critical_addons_enabled = true
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 64
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = length(var.admin_group_object_ids) > 0 ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  auto_scaler_profile {
    scale_down_unneeded              = "10m"
    scale_down_utilization_threshold = "0.5"
    skip_nodes_with_local_storage    = false
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "01:00"
    utc_offset  = "+05:30"
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  lifecycle {
    ignore_changes = [
      # autoscaler owns this after creation
      default_node_pool[0].node_count,
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_size
  mode                  = "User"
  vnet_subnet_id        = var.subnet_id
  zones                 = var.availability_zones
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 128
  tags                  = var.tags

  auto_scaling_enabled = true
  min_count            = var.user_node_min
  max_count            = var.user_node_max

  node_labels = {
    "workload" = "apps"
  }

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
