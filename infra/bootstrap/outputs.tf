output "tfstate_resource_group_name" {
  description = "Terraform state resource group."
  value       = azurerm_resource_group.tfstate.name
}

output "tfstate_storage_account_name" {
  description = "Terraform state storage account."
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  description = "Terraform state blob container."
  value       = azurerm_storage_container.tfstate.name
}

output "tfstate_container_id" {
  description = "Azure Resource Manager ID of the Terraform state container."
  value       = azurerm_storage_container.tfstate.id
}