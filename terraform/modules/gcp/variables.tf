# GCP Module Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "pi_domain" {
  description = "Pi domain name for health checks"
  type        = string
}

variable "dr_webhook_url" {
  description = "External webhook URL for DR notifications"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}
