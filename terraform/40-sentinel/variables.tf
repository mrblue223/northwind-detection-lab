variable "project" {
  type    = string
  default = "northwind"
}

variable "log_retention_days" {
  description = "Keep this low to control cost once outside the free trial window"
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Hard daily ingestion cap - set once you're outside the Sentinel trial's free 10GB/day"
  type        = number
  default     = 1
}
