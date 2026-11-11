output "vnet_id" {
  value = azurerm_virtual_network.lab.id
}

output "vnet_name" {
  value = azurerm_virtual_network.lab.name
}

output "mgmt_subnet_id" {
  value = azurerm_subnet.mgmt.id
}

output "corp_subnet_id" {
  value = azurerm_subnet.corp.id
}

output "mgmt_subnet_prefix" {
  value = var.mgmt_subnet_prefix
}

output "corp_subnet_prefix" {
  value = var.corp_subnet_prefix
}
