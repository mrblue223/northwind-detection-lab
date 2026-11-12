variable "project" {
  description = "Short project name used in resource naming"
  type        = string
  default     = "northwind"
}

variable "location" {
  description = "Azure region for the lab"
  type        = string
  default     = "eastus"
}

variable "budget_amount" {
  description = "Monthly budget amount in USD that triggers alerts"
  type        = number
  default     = 15
}

variable "budget_alert_emails" {
  description = "Email addresses to notify when the budget thresholds are hit"
  type        = list(string)
}

variable "tfstate_storage_account_name" {
  description = "Globally unique name for the Terraform state storage account"
  type        = string
  default     = "stnwdental1127" # Northwind Dental-themed; must be globally unique (adjust the numeric suffix if taken)
}
