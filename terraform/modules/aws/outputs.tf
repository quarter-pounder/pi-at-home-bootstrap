# AWS module outputs

output "s3_bucket_name" {
  description = "S3 bucket name for backups"
  value       = aws_s3_bucket.gitlab_backups.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.gitlab_backups.arn
}

output "aws_access_key_id" {
  description = "AWS access key ID for backup user"
  value       = aws_iam_access_key.gitlab_backup.id
  sensitive   = true
}

output "aws_secret_access_key" {
  description = "AWS secret access key for backup user"
  value       = aws_iam_access_key.gitlab_backup.secret
  sensitive   = true
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.gitlab_alerts.arn
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for backup logs"
  value       = aws_cloudwatch_log_group.gitlab_backup.name
}

output "backup_user_name" {
  description = "IAM user name for backup operations"
  value       = aws_iam_user.gitlab_backup.name
}
