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
  # Accepted trade-offs (see grc/risk-register.md R12 for the cost rationale,
  # tied to the <=$20/mo ceiling in COST_NOTES.md):
  #checkov:skip=CKV_AZURE_59:Public endpoint kept - proper fix is a Private Endpoint + Private DNS Zone (~$8/mo) since GitHub Actions OIDC uses dynamic IPs that can't be firewall-allowlisted; anonymous blob access IS disabled below - R12
  #checkov:skip=CKV2_AZURE_33:Same Private Endpoint (~$8/mo) fix as CKV_AZURE_59 - R12
  #checkov:skip=CKV_AZURE_206:GRS costs ~2x the LRS per-GB rate; kept at LRS for budget discipline (state is a few MB, no production data) - R12
  #checkov:skip=CKV2_AZURE_1:Customer-managed-key encryption needs a managed identity + KV key lifecycle; platform-managed encryption already covers at-rest, so CMK stays a documented stretch goal for lab-only state - R6/R12
  #checkov:skip=CKV_AZURE_33:No queue service is used (blob-only state); classic queue-analytics logging requires a data-plane key path that conflicts with the shared-key-disabled hardening below, for zero benefit - R12
  #checkov:skip=CKV2_AZURE_41:Shared-key auth is disabled below, so SAS tokens cannot be issued and a SAS expiration policy is moot - R12
  name                     = var.tfstate_storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # cheapest replication tier
  min_tls_version          = "TLS1_2"

  # Hardening (Checkov CKV2_AZURE_40): the backend and remote_state data sources
  # authenticate with Azure AD (use_azuread_auth = true), so shared-key auth is
  # disabled entirely. Operators/CI need "Storage Blob Data Contributor" on this
  # account - see VALIDATION_NOTES.md.
  shared_access_key_enabled = false

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
  #checkov:skip=CKV2_AZURE_21:Blob read logging needs a diagnostic setting pointed at a Log Analytics/Event Hub destination not provisioned at the foundation layer (the lab workspace is created later in 40-sentinel); container is private and access is Azure AD-controlled - grc/risk-register.md R12
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Key Vault for secrets shared across stacks (domain admin password,
# Twingate API key, connector tokens, etc.)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "lab" {
  # Accepted trade-offs (see grc/risk-register.md R11). Two kinds:
  # (a) network isolation needs a Private Endpoint + Private DNS Zone (~$8/mo),
  #     unaffordable under the <=$20/mo ceiling AND unworkable with GitHub
  #     Actions OIDC (dynamic IPs that can't be firewall-allowlisted);
  # (b) purge protection is a FREE flag but permanently blocks the destroy/
  #     rebuild lifecycle the lab is built on (the KV name stays reserved for
  #     the retention window), so it is a lifecycle trade-off, not a cost one.
  #checkov:skip=CKV_AZURE_109:Network ACLs need a Private Endpoint (~$8/mo) to work with dynamic-IP CI OIDC - R11
  #checkov:skip=CKV_AZURE_189:Public access kept for the same Private Endpoint (~$8/mo) reason - R11
  #checkov:skip=CKV2_AZURE_32:Private Endpoint + Private DNS Zone (~$8/mo) is the fix; over budget - R11
  #checkov:skip=CKV_AZURE_110:Purge protection (free) permanently blocks the lab's destroy/rebuild lifecycle - R11
  #checkov:skip=CKV_AZURE_42:Recoverability via purge protection off for the same destroy/rebuild reason - R11
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

# Expiry for the generated secrets: creation time + 1 year. On a destroy/rebuild
# the secret is recreated and the window resets; a long-running lab is forced to
# rotate at the one-year mark, which is the behaviour Checkov CKV_AZURE_41 wants.
resource "time_offset" "secret_expiry" {
  offset_days = 365
}

resource "azurerm_key_vault_secret" "domain_admin_password" {
  name            = "domain-admin-password"
  value           = random_password.domain_admin.result
  key_vault_id    = azurerm_key_vault.lab.id
  content_type    = "password"                        # Checkov CKV_AZURE_114
  expiration_date = time_offset.secret_expiry.rfc3339 # Checkov CKV_AZURE_41
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
