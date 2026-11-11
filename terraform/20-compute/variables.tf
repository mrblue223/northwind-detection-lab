variable "project" {
  type    = string
  default = "northwind"
}

variable "vm_size" {
  description = "Size for all three lab VMs. B2s is the practical minimum for a stable DC."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "auto_shutdown_time" {
  description = "24hr HHmm, in auto_shutdown_timezone, to auto-stop VMs if you forget `make down`"
  type        = string
  default     = "2300"
}

variable "auto_shutdown_timezone" {
  type    = string
  default = "Eastern Standard Time"
}

variable "auto_shutdown_notify_emails" {
  type    = list(string)
  default = []
}

variable "scan01_vm_size" {
  description = "Linux scanner host - keep small, Nessus Essentials doesn't need much for a 3-4 host lab"
  type        = string
  default     = "Standard_B2s"
}

variable "scan01_admin_username" {
  type    = string
  default = "scanadmin"
}
