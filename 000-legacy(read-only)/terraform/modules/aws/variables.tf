# AWS module variables

variable "bucket_suffix" {
  description = "Suffix for S3 bucket name to ensure uniqueness"
  type        = string
}

variable "domain" {
  description = "Domain name for GitLab services"
  type        = string
}

variable "alert_email" {
  description = "Email address for alerts and notifications"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
