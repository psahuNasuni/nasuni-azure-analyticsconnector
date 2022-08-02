# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.2"
    }
  }
}

provider "azurerm" {
  features {}

#  use_msi = true
#  subscription_id = var.subscription_id
#  tenant_id       = var.tenant_id
}
