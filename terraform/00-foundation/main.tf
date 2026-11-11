# ---------------------------------------------------------------------------
# Resource group that holds the lab itself (compute, network, etc. go here
# via other stacks). The tfstate storage account lives in its OWN resource
# group so `terraform destroy` on the lab never risks nuking state.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project}-lab"
  location = var.location

  tags = {
    project  = var.project
    purpose  = "detection-engineering-lab"
    teardown = "safe-to-destroy"
  }
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.project}-tfstate"
  location = var.location

  tags = {
    project  = var.project
    purpose  = "terraform-state"
    teardown = "DO-NOT-DESTROY"
  }
}

# ---------------------------------------------------------------------------
# Remote state storage - created once, never destroyed with the rest of the lab
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "tfstate" {
  name                     = var.tfstate_storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # cheapest replication tier
  min_tls_version          = "TLS1_2"

  tags = {
    purpose  = "terraform-state"
    teardown = "DO-NOT-DESTROY"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Key Vault for secrets shared across stacks (domain admin password,
# Twingate API key, connector tokens, etc.)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "lab" {
  name                       = "kv-${var.project}-lab"
  resource_group_name        = azurerm_resource_group.lab.name
  location                   = azurerm_resource_group.lab.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false # allow clean destroy/recreate of the lab
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover",
    ]
  }

  tags = {
    project = var.project
  }
}

# Generate the domain admin / safe mode password once, store it in KV.
# Later stacks read it via a data source instead of generating their own.
resource "random_password" "domain_admin" {
  length           = 24
  special          = true
  override_special = "!@#%^&*()-_=+"
}

resource "azurerm_key_vault_secret" "domain_admin_password" {
  name         = "domain-admin-password"
  value        = random_password.domain_admin.result
  key_vault_id = azurerm_key_vault.lab.id
}

# ---------------------------------------------------------------------------
# Budget alert - created FIRST, before any compute exists.
# Requires an existing Action Group for notifications (created below).
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "budget_alert" {
  name                = "ag-${var.project}-budget"
  resource_group_name = azurerm_resource_group.lab.name
  short_name          = "budgetalrt"

  dynamic "email_receiver" {
    for_each = var.budget_alert_emails
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

resource "azurerm_consumption_budget_resource_group" "lab" {
  name              = "budget-${var.project}-lab"
  resource_group_id = azurerm_resource_group.lab.id

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "GreaterThan"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    contact_emails = var.budget_alert_emails
  }

  lifecycle {
    ignore_changes = [time_period] # avoid perpetual diff on start_date
  }
}
