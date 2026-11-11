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
    storage_account_name = "stnorthwindtfstate"
    container_name       = "tfstate"
    key                  = "05-policy.tfstate"
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
  }
}
