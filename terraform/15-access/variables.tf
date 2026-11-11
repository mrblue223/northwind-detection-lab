variable "project" {
  type    = string
  default = "northwind"
}

variable "twingate_network_name" {
  description = "Your Twingate network slug (the subdomain before .twingate.com)"
  type        = string
}

# NOTE: Twingate group membership is handled via console invite (the
# twingate_group resources below are created with users = []); there is no
# resource that consumes a list of emails. The previously-declared
# admin_user_emails / redteam_user_emails variables were therefore unused
# (flagged by TFLint terraform_unused_declarations) and have been removed.
# See VALIDATION_NOTES.md. If group membership is later driven from Terraform,
# reintroduce them wired to a twingate_users data source + group.users.

variable "enable_redteam_resource" {
  description = <<-EOT
    Toggles the Twingate CIDR Resource covering the whole corp subnet on
    all ports. Keep FALSE by default; flip to true only during `make attack`
    runs. Pairs with var.enable_redteam_access in 10-network (the NSG side).
  EOT
  type        = bool
  default     = false
}

variable "connector_vm_size" {
  type    = string
  default = "Standard_B1s" # cheapest size that reliably runs the connector
}

variable "admin_username" {
  type    = string
  default = "twadmin"
}
