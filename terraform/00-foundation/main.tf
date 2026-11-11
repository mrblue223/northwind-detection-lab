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
  # Accepted lab trade-offs (see grc/risk-register.md R12):
  #checkov:skip=CKV_AZURE_206:LRS is a deliberate cost choice for a destroyable lab (<=$20/mo) - R12
  #checkov:skip=CKV2_AZURE_40:The azurerm backend authenticates with the storage account key; disabling shared-key auth breaks `terraform init` - R12
  #checkov:skip=CKV2_AZURE_33:No private endpoint - operator/CI reach state over the authenticated public endpoint; lab holds no production data - R12
  #checkov:skip=CKV_AZURE_59:Public network access kept so operator/CI can reach the state backend; anonymous blob access is disabled below and the container is private - R12
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys are a documented stretch goal, not a lab requirement - R6/R12
  #checkov:skip=CKV_AZURE_33:Queue service is unused; storage-analytics logging adds cost/noise for no lab benefit - R12
  #checkov:skip=CKV2_AZURE_41:SAS tokens are not used (Azure AD / access key only) - R12
  name                     = var.tfstate_storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # cheapest replication tier
  min_tls_version          = "TLS1_2"

  # Hardening (Checkov CKV_AZURE_59/190, CKV2_AZURE_47): never allow anonymous blob access.
  allow_nested_items_to_be_public = false

  # Hardening (Checkov CKV2_AZURE_38): blob soft-delete so an accidental state delete is recoverable.
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    purpose  = "terraform-state"
    teardown = "DO-NOT-DESTROY"
  }
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging adds cost/noise; state access is controlled via Azure AD and the container is private - grc/risk-register.md R12
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Key Vault for secrets shared across stacks (domain admin password,
# Twingate API key, connector tokens, etc.)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "lab" {
  # Accepted lab trade-offs (see grc/risk-register.md R11). The lab is reached
  # only via Twingate ZTNA and holds no production secrets; a default-deny
  # firewall / private endpoint would block operator + CI + connector access,
  # and purge protection would block the destroy/rebuild lifecycle this lab is
  # built around (purge_protection_enabled is deliberately false below).
  #checkov:skip=CKV_AZURE_109:No network ACLs by design - reached via ZTNA, not a KV firewall - R11
  #checkov:skip=CKV_AZURE_189:Public network access kept so operator/CI/connector can reach KV without private endpoints - R11
  #checkov:skip=CKV_AZURE_110:Purge protection conflicts with the destroyable-lab lifecycle - R11
  #checkov:skip=CKV_AZURE_42:Recoverability (purge protection) deliberately off for the same destroy/rebuild reason - R11
  #checkov:skip=CKV2_AZURE_32:No private endpoint - access is over the authenticated public endpoint, ZTNA-gated at the network layer - R11
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
  #checkov:skip=CKV_AZURE_41:Lab secrets are regenerated on each destroy/rebuild, so a hard expiry date would risk silent mid-lab auth failures with no security gain - grc/risk-register.md R11
  name         = "domain-admin-password"
  value        = random_password.domain_admin.result
  key_vault_id = azurerm_key_vault.lab.id
  content_type = "password" # Checkov CKV_AZURE_114
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
