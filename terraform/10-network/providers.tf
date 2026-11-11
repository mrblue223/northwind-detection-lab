terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnorthwindtfstate" # must match 00-foundation
    container_name       = "tfstate"
    key                  = "10-network.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnorthwindtfstate"
    container_name       = "tfstate"
    key                  = "00-foundation.tfstate"
    use_azuread_auth     = true
  }
}
