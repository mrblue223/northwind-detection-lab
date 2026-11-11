locals {
  rg          = data.terraform_remote_state.foundation.outputs.resource_group_name
  location    = data.terraform_remote_state.foundation.outputs.location
  mgmt_subnet = data.terraform_remote_state.network.outputs.mgmt_subnet_id
}

# ---------------------------------------------------------------------------
# Twingate remote network + connector (logical objects)
# ---------------------------------------------------------------------------
resource "twingate_remote_network" "lab" {
  name = "${var.project}-lab"
}

resource "twingate_connector" "lab" {
  remote_network_id = twingate_remote_network.lab.id
  name              = "${var.project}-connector"
}

resource "twingate_connector_tokens" "lab" {
  connector_id = twingate_connector.lab.id
}

# ---------------------------------------------------------------------------
# Connector VM: smallest Linux size, runs the official connector container
# via cloud-init. This is the one thing in the lab meant to stay always-on.
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "connector" {
  name                = "nic-connector"
  resource_group_name = local.rg
  location            = local.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.mgmt_subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(data.terraform_remote_state.network.outputs.mgmt_subnet_prefix, 10)
  }
}

resource "random_password" "connector_admin" {
  length  = 20
  special = true
}

resource "azurerm_key_vault_secret" "connector_admin_password" {
  name         = "connector-admin-password"
  value        = random_password.connector_admin.result
  key_vault_id = data.terraform_remote_state.foundation.outputs.key_vault_id
}

resource "azurerm_linux_virtual_machine" "connector" {
  name                            = "vm-tg-connector"
  resource_group_name             = local.rg
  location                        = local.location
  size                            = var.connector_vm_size
  admin_username                  = var.admin_username
  admin_password                  = random_password.connector_admin.result
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.connector.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS" # cheapest disk that isn't HDD-slow
    disk_size_gb         = 30                # smallest practical size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-connector.yaml.tpl", {
    access_token  = twingate_connector_tokens.lab.access_token
    refresh_token = twingate_connector_tokens.lab.refresh_token
    network_name  = var.twingate_network_name
  }))

  tags = {
    project   = var.project
    role      = "twingate-connector"
    always_on = "true"
  }
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
resource "twingate_group" "admins" {
  name  = "${var.project}-admins"
  users = [] # populated by twingate_group_users below or via console invite
}

resource "twingate_group" "redteam" {
  name  = "${var.project}-redteam"
  users = []
}

# ---------------------------------------------------------------------------
# Admin resources: narrow, per-host, per-protocol
# ---------------------------------------------------------------------------
resource "twingate_resource" "dc01_admin" {
  name              = "dc01-admin"
  address           = "10.10.2.10"
  remote_network_id = twingate_remote_network.lab.id

  protocols {
    allow_icmp = false
    tcp {
      policy = "RESTRICTED"
      ports  = ["3389", "5985-5986"]
    }
    udp {
      policy = "DENY_ALL"
    }
  }

  access_group {
    group_id = twingate_group.admins.id
  }
}

resource "twingate_resource" "ws01_admin" {
  name              = "ws01-admin"
  address           = "10.10.2.11"
  remote_network_id = twingate_remote_network.lab.id

  protocols {
    allow_icmp = false
    tcp {
      policy = "RESTRICTED"
      ports  = ["3389", "5985-5986"]
    }
    udp {
      policy = "DENY_ALL"
    }
  }

  access_group {
    group_id = twingate_group.admins.id
  }
}

resource "twingate_resource" "scan01_admin" {
  name              = "scan01-admin"
  address           = "10.10.1.11"
  remote_network_id = twingate_remote_network.lab.id

  protocols {
    allow_icmp = true
    tcp {
      policy = "RESTRICTED"
      ports  = ["22"]
    }
    udp {
      policy = "DENY_ALL"
    }
  }

  access_group {
    group_id = twingate_group.admins.id
  }
}

resource "twingate_resource" "fs01_admin" {
  name              = "fs01-admin"
  address           = "10.10.2.12"
  remote_network_id = twingate_remote_network.lab.id

  protocols {
    allow_icmp = false
    tcp {
      policy = "RESTRICTED"
      ports  = ["445", "3389", "5985-5986"]
    }
    udp {
      policy = "DENY_ALL"
    }
  }

  access_group {
    group_id = twingate_group.admins.id
  }
}

# ---------------------------------------------------------------------------
# Red-team CIDR resource: broad, toggleable, models "already past the ZTNA
# checkpoint" (e.g. a compromised endpoint's session). Paired with the NSG
# toggle in 10-network - both must be true for attack traffic to flow.
# ---------------------------------------------------------------------------
resource "twingate_resource" "corp_redteam" {
  count             = var.enable_redteam_resource ? 1 : 0
  name              = "corp-redteam-cidr"
  address           = "10.10.2.0/24"
  remote_network_id = twingate_remote_network.lab.id

  protocols {
    allow_icmp = true
    tcp {
      policy = "ALLOW_ALL"
    }
    udp {
      policy = "ALLOW_ALL"
    }
  }

  access_group {
    group_id = twingate_group.redteam.id
  }
}
