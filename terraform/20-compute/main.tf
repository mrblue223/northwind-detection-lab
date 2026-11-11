locals {
  rg          = data.terraform_remote_state.foundation.outputs.resource_group_name
  location    = data.terraform_remote_state.foundation.outputs.location
  corp_subnet = data.terraform_remote_state.network.outputs.corp_subnet_id
  mgmt_subnet = data.terraform_remote_state.network.outputs.mgmt_subnet_id

  hosts = {
    dc01 = { ip = "10.10.2.10", image = "win2022", computer_name = "DC01" }
    ws01 = { ip = "10.10.2.11", image = "win11", computer_name = "WS01" }
    fs01 = { ip = "10.10.2.12", image = "win2022", computer_name = "FS01" }
  }

  images = {
    win2022 = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2022-datacenter-azure-edition"
      version   = "latest"
    }
    win11 = {
      publisher = "MicrosoftWindowsDesktop"
      offer     = "windows-11"
      sku       = "win11-23h2-pro"
      version   = "latest"
    }
  }
}

resource "azurerm_network_interface" "host" {
  for_each            = local.hosts
  name                = "nic-${each.key}"
  resource_group_name = local.rg
  location            = local.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.corp_subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_windows_virtual_machine" "host" {
  # Accepted lab trade-offs (see grc/risk-register.md R14/R15). Managed disks are
  # already platform-encrypted at rest; host-level encryption needs the
  # EncryptionAtHost subscription feature and adds setup cost for no lab benefit.
  # The Azure Monitor agent extension (azurerm_virtual_machine_extension.ama) is
  # required telemetry for the detection pipeline, not optional tooling.
  #checkov:skip=CKV_AZURE_151:Host encryption not enabled - disks are platform-encrypted at rest; EncryptionAtHost is out of scope for the lab - R15
  #checkov:skip=CKV_AZURE_50:The Azure Monitor agent extension is the telemetry pipeline this detection lab exists for - R14
  for_each            = local.hosts
  name                = each.key
  computer_name       = each.value.computer_name
  resource_group_name = local.rg
  location            = local.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = data.azurerm_key_vault_secret.domain_admin_password.value

  network_interface_ids = [azurerm_network_interface.host[each.key].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS" # avoid Premium - this is the main always-present cost
  }

  source_image_reference {
    publisher = local.images[each.value.image].publisher
    offer     = local.images[each.value.image].offer
    sku       = local.images[each.value.image].sku
    version   = local.images[each.value.image].version
  }

  tags = {
    project = var.project
    role    = each.key
  }
}

# Auto-shutdown as a safety net in case `make down` is forgotten. This does
# NOT replace `make down` for cost purposes - a scheduled shutdown stops the
# VM (OS-level) but the compute allocation and its minute-billing only truly
# stops on deallocation, which `make down` (terraform destroy on this stack)
# provides. Treat this as a backstop, not the primary cost control.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "host" {
  for_each           = local.hosts
  virtual_machine_id = azurerm_windows_virtual_machine.host[each.key].id
  location           = local.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled         = length(var.auto_shutdown_notify_emails) > 0
    email           = length(var.auto_shutdown_notify_emails) > 0 ? var.auto_shutdown_notify_emails[0] : null
    time_in_minutes = 30
  }
}

# Azure Monitor Agent - ships Windows Event Log + (once installed) Sysmon
# data to the Log Analytics workspace. DCR + DCR association happen in
# 40-sentinel since that's where the workspace lives; this just gets the
# agent itself onto each VM.
resource "azurerm_virtual_machine_extension" "ama" {
  for_each                   = local.hosts
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

# ---------------------------------------------------------------------------
# SCAN01: dedicated vulnerability-scanning host (Nessus Essentials).
# Linux, placed in `mgmt` (it's security tooling infrastructure, not part
# of the business network it scans) at a fixed IP so 10-network can grant
# it - and only it - a narrow, permanent path into `corp` on scan-relevant
# ports. This is deliberately separate from the toggleable red-team path:
# scanning is a legitimate, ongoing operational function, not an attack
# simulation, so it doesn't get gated the same way.
# ---------------------------------------------------------------------------
resource "tls_private_key" "scan01" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "time_offset" "secret_expiry" {
  offset_days = 365 # creation + 1 year; resets on rebuild (Checkov CKV_AZURE_41)
}

resource "azurerm_key_vault_secret" "scan01_ssh_private_key" {
  name            = "scan01-ssh-private-key"
  value           = tls_private_key.scan01.private_key_pem
  key_vault_id    = data.terraform_remote_state.foundation.outputs.key_vault_id
  content_type    = "application/x-pem-file"          # Checkov CKV_AZURE_114
  expiration_date = time_offset.secret_expiry.rfc3339 # Checkov CKV_AZURE_41
}

resource "azurerm_network_interface" "scan01" {
  name                = "nic-scan01"
  resource_group_name = local.rg
  location            = local.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.mgmt_subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.11" # .10 is the Twingate Connector, see 15-access
  }
}

resource "azurerm_linux_virtual_machine" "scan01" {
  #checkov:skip=CKV_AZURE_50:The Azure Monitor agent extension is required telemetry for the detection lab - grc/risk-register.md R14
  name                = "scan01"
  computer_name       = "scan01"
  resource_group_name = local.rg
  location            = local.location
  size                = var.scan01_vm_size
  admin_username      = var.scan01_admin_username

  network_interface_ids           = [azurerm_network_interface.scan01.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.scan01_admin_username
    public_key = tls_private_key.scan01.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32 # Nessus itself is lightweight; this just needs room for scan results/plugins
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    project = var.project
    role    = "vuln-scanner"
  }
}

resource "azurerm_virtual_machine_extension" "ama_linux_scan01" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.scan01.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.25"
  auto_upgrade_minor_version = true
}
