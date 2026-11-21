provider "azurerm" {
  features {
    resource_group {
      # lab clusters get torn down often; don't block on leftovers
      prevent_deletion_if_contains_resources = false
    }
  }
  # subscription_id / tenant_id come from ARM_* env vars or az login
}
