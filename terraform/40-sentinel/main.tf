locals {
  rg       = data.terraform_remote_state.foundation.outputs.resource_group_name
  location = data.terraform_remote_state.foundation.outputs.location
  vm_ids   = data.terraform_remote_state.compute.outputs.host_vm_ids
}

resource "azurerm_log_analytics_workspace" "lab" {
  name                = "law-${var.project}-lab"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.daily_quota_gb # set low once outside the free trial window
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "lab" {
  workspace_id = azurerm_log_analytics_workspace.lab.id
}

# ---------------------------------------------------------------------------
# Data Collection Rule: Windows Security Events + Sysmon (via the custom
# Sysmon channel). Associated to all three VMs.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_data_collection_rule" "windows_security" {
  name                = "dcr-${var.project}-windows-security"
  resource_group_name = local.rg
  location            = local.location

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.lab.id
      name                  = "lab-law"
    }
  }

  data_flow {
    streams      = ["Microsoft-SecurityEvent", "Microsoft-Event"]
    destinations = ["lab-law"]
  }

  data_sources {
    windows_event_log {
      name           = "security-events"
      streams        = ["Microsoft-SecurityEvent"]
      x_path_queries = ["Security!*"]
    }

    windows_event_log {
      name           = "sysmon-events"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["Microsoft-Windows-Sysmon/Operational!*"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "windows_security" {
  for_each                = local.vm_ids
  name                    = "dcra-${each.key}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows_security.id
}

# ---------------------------------------------------------------------------
# Analytics rules - one per file in ../../detections/*.kql
# ---------------------------------------------------------------------------
locals {
  detection_files = fileset("${path.module}/../../detections", "*.kql")

  detections = {
    "01-phishing-execution" = {
      name       = "Phishing payload execution on WS01"
      severity   = "High"
      tactics    = ["InitialAccess", "Execution"]
      techniques = ["T1566", "T1204"]
    }
    "02-c2-callback" = {
      name       = "Unusual outbound connection from WS01"
      severity   = "High"
      tactics    = ["CommandAndControl"]
      techniques = ["T1071", "T1105"]
    }
    "03-credential-dumping" = {
      name       = "LSASS memory access (credential dumping)"
      severity   = "High"
      tactics    = ["CredentialAccess"]
      techniques = ["T1003"]
    }
    "04-kerberoasting" = {
      name       = "Kerberoasting - RC4 service ticket requests"
      severity   = "High"
      tactics    = ["CredentialAccess"]
      techniques = ["T1558"]
    }
    "05-lateral-movement" = {
      name       = "Lateral movement WS01 -> FS01"
      severity   = "Medium"
      tactics    = ["LateralMovement"]
      techniques = ["T1021"]
    }
    "06-persistence" = {
      name       = "Persistence - new admin/service/scheduled task"
      severity   = "High"
      tactics    = ["Persistence"]
      techniques = ["T1136", "T1053", "T1543"]
    }
    "08-coercion-pipe-access" = {
      name       = "Coercion attempt - EFSRPC/spooler pipe access on DC01"
      severity   = "High"
      tactics    = ["CredentialAccess"]
      techniques = ["T1187"]
    }
    "09-ntlm-relay-dc-machine-account" = {
      name       = "DC machine account authenticated to a workstation (relay signature)"
      severity   = "High"
      tactics    = ["CredentialAccess", "LateralMovement"]
      techniques = ["T1557"]
    }
    "10-dcsync-rights-abuse" = {
      name       = "DCSync - replication rights exercised by a non-DC principal"
      severity   = "High"
      tactics    = ["CredentialAccess"]
      techniques = ["T1003"]
    }
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "detections" {
  for_each                   = local.detections
  name                       = each.key
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  display_name               = each.value.name
  severity                   = each.value.severity
  query                      = file("${path.module}/../../detections/${each.key}.kql")
  query_frequency            = "PT10M"
  query_period               = "PT10M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  tactics                    = each.value.tactics
  techniques                 = each.value.techniques
  enabled                    = true

  incident_configuration {
    create_incident = true
    grouping {
      enabled                 = true
      lookback_duration       = "PT1H"
      reopen_closed_incidents = false
      entity_matching_method  = "AllEntities"
    }
  }
}
