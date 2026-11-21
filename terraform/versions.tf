terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in a storage account. Values come from -backend-config so the
  # same code works for a throwaway lab and a shared env. See `make init`.
  backend "azurerm" {}
}
