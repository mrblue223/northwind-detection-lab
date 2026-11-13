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
  type = string
  # NOT the cheaper burstable Standard_B1s: the B-series is frequently
  # capacity-restricted in eastus (apply fails at VM create with 409
  # SkuNotAvailable / "Capacity Restrictions"), so B1s cannot be relied on to
  # deploy there. This is an AVAILABILITY choice, not a cost one - F1als_v7
  # (1 vCPU / 2 GB) is marginally pricier but actually provisions. Revisit if
  # B-series capacity frees up, or when deploying to a region where B1s is
  # reliably available.
  default = "Standard_F1als_v7"
}

variable "admin_username" {
  type    = string
  default = "twadmin"
}
