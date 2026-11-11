terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    twingate = {
      source = "Twingate/twingate"
      # Pinned to the 3.x series deliberately: v4 introduced breaking schema
      # changes (access_group -> access_groups, singular -> plural blocks,
      # added is_authoritative). The resource syntax in this stack
      # (access_group { group_id = ... }, protocols { tcp { policy, ports } })
      # matches 3.x. Upgrading to 4.x requires rewriting main.tf, not just
      # bumping this constraint - verify against current provider docs first.
      version = "~> 3.0"
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
    storage_account_name = "stnorthwindtfstate" # must match 00-foundation
    container_name       = "tfstate"
    key                  = "15-access.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

# Twingate API token: generate in Twingate Admin Console (Settings > API),
# store it in Key Vault (`twingate-api-token`) rather than a tfvars file.
provider "twingate" {
  api_token = data.azurerm_key_vault_secret.twingate_api_token.value
  network   = var.twingate_network_name
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

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-northwind-tfstate"
    storage_account_name = "stnorthwindtfstate"
    container_name       = "tfstate"
    key                  = "10-network.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_key_vault_secret" "twingate_api_token" {
  name         = "twingate-api-token"
  key_vault_id = data.terraform_remote_state.foundation.outputs.key_vault_id
}
