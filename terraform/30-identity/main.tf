# NOTE: these are CLOUD-ONLY Entra ID users, separate from the on-prem AD
# accounts Ansible creates on DC01. We are deliberately skipping Entra
# Connect sync (documented limitation - see PLAN.md). The purpose of this
# stack is purely to generate realistic Entra sign-in/audit log telemetry
# for Sentinel, not to provide hybrid identity.

locals {
  users = csvdecode(file("${path.module}/../../data/users.csv"))
}

resource "random_password" "user" {
  for_each = { for u in local.users : u.samaccountname => u }
  length   = 16
  special  = true
}

resource "azuread_user" "lab" {
  for_each = { for u in local.users : u.samaccountname => u }

  user_principal_name   = "${each.value.samaccountname}@${var.tenant_domain}"
  display_name          = "${each.value.first_name} ${each.value.last_name}"
  department            = each.value.department
  job_title             = each.value.title
  password              = random_password.user[each.key].result
  force_password_change = true
}

resource "azuread_group" "department" {
  for_each         = toset([for u in local.users : u.department])
  display_name     = "NW-${each.value}"
  security_enabled = true
}

resource "azuread_group_member" "department" {
  for_each = { for u in local.users : u.samaccountname => u }

  group_object_id  = azuread_group.department[each.value.department].object_id
  member_object_id = azuread_user.lab[each.key].object_id
}
