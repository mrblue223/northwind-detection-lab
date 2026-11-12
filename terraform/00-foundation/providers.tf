terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Bootstrap note: this backend block points at the storage account THIS stack
  # creates. On the very first `terraform init` in this folder, comment this
  # block out and use local state, apply once to create the storage account,
  # then uncomment, re-run `terraform init -migrate-state`, and never touch it
  # again. All other stacks (10-network, 15-access, 20-compute, ...) use this
  # backend from the start via `terraform_remote_state` data sources.
  backend "azurerm" {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnwdental1127" # must match variables.tf default (globally unique; adjust suffix if taken)
    container_name       = "tfstate"
    key                  = "00-foundation.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}
