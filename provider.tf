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

  use_msi = true
  subscription_id = "fb43991d-325b-404b-b0cd-9319b558a03f"
  tenant_id       = "146173a2-cdda-476f-b6d5-a48c6e6dd0c0"
}
