terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnwdental1127"
    container_name       = "tfstate"
    key                  = "20-compute.tfstate"
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

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnwdental1127"
    container_name       = "tfstate"
    key                  = "10-network.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_key_vault_secret" "domain_admin_password" {
  name         = "domain-admin-password"
  key_vault_id = data.terraform_remote_state.foundation.outputs.key_vault_id
}
