# Terraform Variables

# Cloudflare Configuration
variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS and tunnel management"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domain name for GitLab services"
  type        = string
  default     = "example.com"
}

variable "cloudflare_tunnel_name" {
  description = "Name for the Cloudflare tunnel"
  type        = string
  default     = "gitlab-pi"
}

variable "pi5_ip" {
  description = "IP address of the Raspberry Pi 5"
  type        = string
  default     = ""
}

variable "grafana_port" {
  description = "Port for Grafana service"
  type        = number
  default     = 3000
}

# Cloud Provider Selection
variable "use_gcp" {
  description = "Use GCP instead of AWS (GCP has better Always Free Tier)"
  type        = bool
  default     = true
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# GCP Configuration
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "alert_email" {
  description = "Email address for alerts and notifications"
  type        = string
  default     = ""
}

variable "dr_webhook_url" {
  description = "External webhook URL for DR notifications"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

# Optional: Environment-specific settings
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {
    Project     = "gitlab-pi"
    ManagedBy   = "terraform"
    Environment = "prod"
  }
}
