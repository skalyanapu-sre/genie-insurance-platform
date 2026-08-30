provider "azurerm" {
  features {}

  resource_provider_registrations = "none"

  # Required because the Terraform state Storage Account
  # has Shared Key authentication disabled.
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}