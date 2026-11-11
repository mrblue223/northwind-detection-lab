output "connector_private_ip" {
  value = azurerm_network_interface.connector.private_ip_address
}

output "remote_network_id" {
  value = twingate_remote_network.lab.id
}

output "admins_group_id" {
  value = twingate_group.admins.id
}

output "redteam_group_id" {
  value = twingate_group.redteam.id
}
