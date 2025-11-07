#Terraform Outputs

# Cloudflare outputs
output "cloudflare_tunnel_id" {
  description = "Cloudflare tunnel ID"
  value       = module.cloudflare.tunnel_id
  sensitive   = false
}

output "cloudflare_tunnel_token" {
  description = "Cloudflare tunnel token for Pi setup"
  value       = module.cloudflare.tunnel_token
  sensitive   = true
}

output "dns_records" {
  description = "DNS records created"
  value       = module.cloudflare.dns_records
  sensitive   = false
}

# AWS outputs
output "s3_bucket_name" {
  description = "S3 bucket name for backups"
  value       = module.aws.s3_bucket_name
  sensitive   = false
}

output "aws_access_key_id" {
  description = "AWS access key ID for backup user"
  value       = module.aws.aws_access_key_id
  sensitive   = true
}

output "aws_secret_access_key" {
  description = "AWS secret access key for backup user"
  value       = module.aws.aws_secret_access_key
  sensitive   = true
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = module.aws.sns_topic_arn
  sensitive   = false
}

# GCP outputs
output "gcp_backup_bucket" {
  description = "GCS bucket for backups"
  value       = var.use_gcp ? module.gcp[0].backup_bucket : null
  sensitive   = false
}

output "gcp_service_account_email" {
  description = "GCP service account email"
  value       = var.use_gcp ? module.gcp[0].service_account_email : null
  sensitive   = false
}

output "gcp_dr_webhook_url" {
  description = "GCP Cloud Function URL for DR webhooks"
  value       = var.use_gcp ? module.gcp[0].dr_webhook_function_url : null
  sensitive   = false
}

output "gcp_pubsub_topic" {
  description = "GCP Pub/Sub topic for DR notifications"
  value       = var.use_gcp ? module.gcp[0].pubsub_topic : null
  sensitive   = false
}

# Combined outputs for easy .env generation
output "env_variables" {
  description = "Environment variables for .env file"
  value = {
    CLOUDFLARE_TUNNEL_TOKEN = module.cloudflare.tunnel_token
    BACKUP_BUCKET          = var.use_gcp ? "gs://${module.gcp[0].backup_bucket}" : "s3://${module.aws.s3_bucket_name}"
    AWS_ACCESS_KEY_ID      = var.use_gcp ? null : module.aws.aws_access_key_id
    AWS_SECRET_ACCESS_KEY  = var.use_gcp ? null : module.aws.aws_secret_access_key
    GCP_PROJECT_ID         = var.use_gcp ? var.gcp_project_id : null
    GCP_SERVICE_ACCOUNT    = var.use_gcp ? module.gcp[0].service_account_email : null
    DR_WEBHOOK_URL         = var.use_gcp ? module.gcp[0].dr_webhook_function_url : null
  }
  sensitive = true
}
