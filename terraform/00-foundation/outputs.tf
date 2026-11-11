output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "location" {
  value = azurerm_resource_group.lab.location
}

output "key_vault_id" {
  value = azurerm_key_vault.lab.id
}

output "key_vault_name" {
  value = azurerm_key_vault.lab.name
}

output "tfstate_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}
