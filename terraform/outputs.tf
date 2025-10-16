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

# Combined outputs for easy .env generation
output "env_variables" {
  description = "Environment variables for .env file"
  value = {
    CLOUDFLARE_TUNNEL_TOKEN = module.cloudflare.tunnel_token
    BACKUP_BUCKET          = "s3://${module.aws.s3_bucket_name}"
    AWS_ACCESS_KEY_ID      = module.aws.aws_access_key_id
    AWS_SECRET_ACCESS_KEY  = module.aws.aws_secret_access_key
  }
  sensitive = true
}
