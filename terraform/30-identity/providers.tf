terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnorthwindtfstate"
    container_name       = "tfstate"
    key                  = "30-identity.tfstate"
  }
}

provider "azuread" {}
