# ============================================================
# Local Values
# ============================================================

locals {
  common_tags = {
    managed_by = "terraform"
    purpose    = "terraform-state"
    project    = "genie-insurance-platform"
  }
}


# ============================================================
# Terraform State Resource Group
# ============================================================
#
# This resource group already exists and is imported into
# Terraform state.
#
# Organizational tags may be managed outside this Terraform
# stack, so this bootstrap configuration does not overwrite
# existing resource-group tags.
#

resource "azurerm_resource_group" "tfstate" {
  name     = var.tfstate_resource_group_name
  location = var.location

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      tags
    ]
  }
}


# ============================================================
# Terraform State Storage Account
# ============================================================
#
# The storage account already exists in Azure.
#
# It will be imported into Terraform state rather than recreated.
#

resource "azurerm_storage_account" "tfstate" {
  name                = var.tfstate_storage_account_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Require HTTPS and TLS 1.2.
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Prevent anonymous/public access to blobs and containers.
  allow_nested_items_to_be_public = false

  # Use Microsoft Entra ID authentication instead of
  # Storage Account shared keys.
  shared_access_key_enabled = false

  # GitHub-hosted runners currently require access through
  # the public Azure Storage endpoint.
  #
  # Public network access does NOT make the container public.
  # Authentication and Azure RBAC are still required.
  public_network_access_enabled = true

  # NOTE:
  # Do not enable infrastructure_encryption_enabled here until
  # the existing account has been inspected. Changing this
  # setting on an existing account can force replacement.

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags
    ]
  }
}


# ============================================================
# Terraform State Blob Container
# ============================================================
#
# The container contains Terraform state files.
#
# It must never permit anonymous/public access.
#

resource "azurerm_storage_container" "tfstate" {
  name               = var.tfstate_container_name
  storage_account_id = azurerm_storage_account.tfstate.id

  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}


# ============================================================
# GitHub Actions Access to Terraform State
# ============================================================
#
# GitHub Actions authenticates to Azure through OIDC.
#
# This role gives the GitHub Terraform service principal
# data-plane access to the Terraform state container.
#
# Required operations include:
#
#   - Read Terraform state
#   - Write Terraform state
#   - Update Terraform state
#   - State locking
#
# The role is intentionally scoped to the tfstate container
# rather than the entire Azure subscription.
#

resource "azurerm_role_assignment" "github_tfstate" {
  count = var.github_actions_principal_object_id != null ? 1 : 0

  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.github_actions_principal_object_id
  principal_type       = "ServicePrincipal"
}