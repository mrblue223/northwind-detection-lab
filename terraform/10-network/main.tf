locals {
  rg       = data.terraform_remote_state.foundation.outputs.resource_group_name
  location = data.terraform_remote_state.foundation.outputs.location
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${var.project}-lab"
  resource_group_name = local.rg
  location            = local.location
  address_space       = var.vnet_address_space
}

# ---------------------------------------------------------------------------
# mgmt subnet: Twingate Connector, optional Ansible control VM / SET relay VM
# ---------------------------------------------------------------------------
resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "nsg-mgmt"
  resource_group_name = local.rg
  location            = local.location

  # No inbound rules from Internet at all. The Connector only makes
  # OUTBOUND connections to Twingate's control plane - this is the whole
  # point of ZTNA. Default AzureNSG rules already deny all other inbound.
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

# ---------------------------------------------------------------------------
# corp subnet: DC01, WS01, FS01
# ---------------------------------------------------------------------------
resource "azurerm_subnet" "corp" {
  name                 = "snet-corp"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.corp_subnet_prefix]
}

resource "azurerm_network_security_group" "corp" {
  name                = "nsg-corp"
  resource_group_name = local.rg
  location            = local.location

  # Allow all intra-CORP traffic (AD needs a lot of ports between DC/WS/FS).
  # IMPORTANT: scoped to the corp subnet prefix specifically, NOT the
  # "VirtualNetwork" service tag. Using "VirtualNetwork" here would match
  # mgmt-subnet traffic too (since both subnets share one VNet) at a lower
  # priority number than the scanner/red-team rules below, silently
  # defeating the whole mgmt<->corp segmentation story those rules exist
  # to enforce. Keep this scoped to corp-internal traffic only.
  security_rule {
    name                       = "Allow-Corp-Internal"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.corp_subnet_prefix
    destination_address_prefix = var.corp_subnet_prefix
  }

  # Explicit deny of anything from Internet, even though default rules
  # already cover this - documented here so the intent is visible in code.
  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "corp" {
  subnet_id                 = azurerm_subnet.corp.id
  network_security_group_id = azurerm_network_security_group.corp.id
}

# ---------------------------------------------------------------------------
# Scanner access rule: SCAN01 (mgmt, fixed IP .11) -> corp, permanent and
# narrow. Unlike the red-team rule below, this is NOT toggled - vulnerability
# scanning is an ongoing operational function, not an attack simulation.
# Scoped to SCAN01's single IP rather than the whole mgmt subnet, and to
# common scan-relevant ports rather than "*", to keep this genuinely narrow
# even though it's always-on.
# ---------------------------------------------------------------------------
resource "azurerm_network_security_rule" "scanner_to_corp" {
  name                         = "Allow-Scanner-To-Corp"
  priority                     = 140
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_ranges      = ["22", "135", "139", "445", "3389", "5985", "5986", "49152-65535"]
  source_address_prefix        = "10.10.1.11/32" # SCAN01's fixed IP - see 20-compute
  destination_address_prefix   = var.corp_subnet_prefix
  resource_group_name          = local.rg
  network_security_group_name  = azurerm_network_security_group.corp.name
}

# ---------------------------------------------------------------------------
# Red-team access rule: mgmt -> corp on AD/attack-relevant ports.
# This is DELIBERATE and toggled by var.enable_redteam_access. It models
# "attacker already has a foothold inside the perimeter" (post-phishing),
# not an open door to the internet. Document this prominently in the README.
# ---------------------------------------------------------------------------
resource "azurerm_network_security_rule" "redteam_mgmt_to_corp" {
  count = var.enable_redteam_access ? 1 : 0

  name                        = "Allow-Mgmt-To-Corp-RedTeam"
  priority                    = 150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["53", "88", "135", "389", "445", "3268", "3389", "5985", "5986"]
  source_address_prefix       = var.mgmt_subnet_prefix
  destination_address_prefix  = var.corp_subnet_prefix
  resource_group_name         = local.rg
  network_security_group_name = azurerm_network_security_group.corp.name
}
