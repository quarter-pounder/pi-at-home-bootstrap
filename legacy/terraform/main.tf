# Manages cloud resources for GitLab Pi setup

terraform {
  required_version = ">= 1.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure providers
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Random ID for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Cloudflare resources
module "cloudflare" {
  source = "./modules/cloudflare"

  domain               = var.domain
  tunnel_name          = var.cloudflare_tunnel_name
  pi5_ip               = var.pi5_ip
  grafana_port         = var.grafana_port
}

# AWS resources
module "aws" {
  source = "./modules/aws"

  bucket_suffix        = random_id.bucket_suffix.hex
  domain               = var.domain
  alert_email          = var.alert_email
  backup_retention_days = var.backup_retention_days
}

# GCP resources (Always Free Tier)
module "gcp" {
  source = "./modules/gcp"
  count  = var.use_gcp ? 1 : 0

  project_id            = var.gcp_project_id
  region               = var.gcp_region
  pi_domain            = var.domain
  dr_webhook_url       = var.dr_webhook_url
  notification_email   = var.alert_email
  backup_retention_days = var.backup_retention_days
}
