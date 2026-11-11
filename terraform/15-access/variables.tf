variable "project" {
  type    = string
  default = "northwind"
}

variable "twingate_network_name" {
  description = "Your Twingate network slug (the subdomain before .twingate.com)"
  type        = string
}

variable "admin_user_emails" {
  description = "Emails of users who should get admin (RDP/WinRM/SSH) access"
  type        = list(string)
}

variable "redteam_user_emails" {
  description = "Emails of users who should get the broad red-team CIDR resource. Usually the same as admin_user_emails for a solo lab."
  type        = list(string)
}

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
