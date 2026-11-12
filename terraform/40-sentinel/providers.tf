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
    storage_account_name = "stnwdental1127"
    container_name       = "tfstate"
    key                  = "40-sentinel.tfstate"
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
    storage_account_name = "stnwdental1127"
    container_name       = "tfstate"
    key                  = "00-foundation.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "compute" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnwdental1127"
    container_name       = "tfstate"
    key                  = "20-compute.tfstate"
    use_azuread_auth     = true
  }
}
