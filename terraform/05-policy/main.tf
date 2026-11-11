locals {
  rg = data.terraform_remote_state.foundation.outputs.resource_group_name
}

# ---------------------------------------------------------------------------
# These are Azure's built-in policy definitions, looked up by display name
# rather than hardcoded GUIDs (built-in IDs are stable but display names are
# easier to verify against the portal - Policy > Definitions). CONFIRM each
# one still exists under this exact name before applying; Microsoft
# occasionally renames or supersedes built-ins.
# ---------------------------------------------------------------------------

data "azurerm_policy_definition" "no_public_ip_on_nic" {
  display_name = "Network interfaces should not have public IPs"
}

data "azurerm_policy_definition" "require_tag" {
  display_name = "Require a tag on resources"
}

data "azurerm_policy_definition" "allowed_locations" {
  display_name = "Allowed locations"
}

# ---------------------------------------------------------------------------
# Turns the "no public IPs anywhere" intent documented in 10-network's
# comments into something actually enforced, not just a convention a future
# PR could quietly break.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group_policy_assignment" "no_public_ip" {
  name                 = "no-public-ip-on-nic"
  resource_group_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.rg}"
  policy_definition_id = data.azurerm_policy_definition.no_public_ip_on_nic.id
  description          = "Enforces the lab's no-public-IP network design. Audit effect: this built-in does not support Deny."
}

resource "azurerm_resource_group_policy_assignment" "require_project_tag" {
  name                 = "require-project-tag"
  resource_group_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.rg}"
  policy_definition_id = data.azurerm_policy_definition.require_tag.id
  description          = "Blocks creation of any resource missing the 'project' tag - keeps cost attribution and the teardown story honest."

  parameters = jsonencode({
    tagName = {
      value = "project"
    }
  })
}

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  resource_group_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.rg}"
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id
  description          = "Prevents an accidental resource creation in an unexpected region (a real-world source of both surprise cost and untracked attack surface)."

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = [var.location]
    }
  })
}

data "azurerm_client_config" "current" {}
