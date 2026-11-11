output "host_private_ips" {
  value = { for k, v in local.hosts : k => v.ip }
}

output "host_vm_ids" {
  value = { for k, v in azurerm_windows_virtual_machine.host : k => v.id }
}

output "scan01_private_ip" {
  value = azurerm_network_interface.scan01.private_ip_address
}

output "scan01_vm_id" {
  value = azurerm_linux_virtual_machine.scan01.id
}
