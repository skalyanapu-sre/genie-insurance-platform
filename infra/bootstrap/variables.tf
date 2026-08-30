variable "location" {
  description = "Azure region used for the Terraform backend resources."
  type        = string
  default     = "eastus"
}

variable "tfstate_resource_group_name" {
  description = "Resource group dedicated to Terraform remote state."
  type        = string
  default     = "mqgen-tfstate-rg"
}

variable "tfstate_container_name" {
  description = "Blob container used to store Terraform state files."
  type        = string
  default     = "tfstate"
}

variable "environment" {
  description = "Environment associated with the bootstrap deployment."
  type        = string
  default     = "shared"
}

variable "github_actions_principal_object_id" {
  description = "Microsoft Entra service principal Object ID used by GitHub Actions."
  type        = string
  default     = null
  nullable    = true
}

variable "tfstate_storage_account_name" {
  description = "Name of the existing Azure Storage Account used for Terraform remote state."
  type        = string
}