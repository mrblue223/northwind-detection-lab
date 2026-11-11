variable "project" {
  type    = string
  default = "northwind"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "mgmt_subnet_prefix" {
  description = "Subnet for the Twingate Connector (and optional control/relay VMs)"
  type        = string
  default     = "10.10.1.0/24"
}

variable "corp_subnet_prefix" {
  description = "Subnet for DC01, WS01, FS01"
  type        = string
  default     = "10.10.2.0/24"
}

variable "enable_redteam_access" {
  description = <<-EOT
    Toggles the NSG rule that allows mgmt -> corp on attack-relevant ports.
    Keep this FALSE by default. Flip to true only during `make attack` runs,
    then back to false. This is the network-layer half of the red-team
    access story; the Twingate CIDR Resource in 15-access is the other half.
  EOT
  type    = bool
  default = false
}
