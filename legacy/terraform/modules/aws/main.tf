# Manages S3 backups, IAM, and monitoring

# S3 bucket for GitLab backups
resource "aws_s3_bucket" "gitlab_backups" {
  bucket = "gitlab-pi-backups-${var.bucket_suffix}"

  tags = merge(var.tags, {
    Name        = "GitLab Pi Backups"
    Purpose     = "backup-storage"
    Environment = var.environment
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  rule {
    id     = "backup_retention"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM user for GitLab backup operations
resource "aws_iam_user" "gitlab_backup" {
  name = "gitlab-pi-backup-${var.bucket_suffix}"
  path = "/gitlab-pi/"

  tags = merge(var.tags, {
    Name    = "GitLab Pi Backup User"
    Purpose = "backup-operations"
  })
}

# IAM access key for backup user
resource "aws_iam_access_key" "gitlab_backup" {
  user = aws_iam_user.gitlab_backup.name
}

# IAM policy for backup operations
resource "aws_iam_user_policy" "gitlab_backup" {
  name = "gitlab-backup-policy"
  user = aws_iam_user.gitlab_backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.gitlab_backups.arn,
          "${aws_s3_bucket.gitlab_backups.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketVersioning"
        ]
        Resource = "*"
      }
    ]
  })
}

# SNS topic for alerts
resource "aws_sns_topic" "gitlab_alerts" {
  name = "gitlab-pi-alerts-${var.bucket_suffix}"

  tags = merge(var.tags, {
    Name    = "GitLab Pi Alerts"
    Purpose = "notifications"
  })
}

# SNS topic subscription (email)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.gitlab_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch log group for backup logs
resource "aws_cloudwatch_log_group" "gitlab_backup" {
  name              = "/gitlab-pi/backup"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name    = "GitLab Pi Backup Logs"
    Purpose = "logging"
  })
}

# CloudWatch metric filter for backup failures
resource "aws_cloudwatch_log_metric_filter" "backup_failure" {
  name           = "gitlab-backup-failure"
  log_group_name = aws_cloudwatch_log_group.gitlab_backup.name
  pattern        = "[timestamp, request_id, level=\"ERROR\", message=\"*backup*failed*\"]"

  metric_transformation {
    name      = "GitLabBackupFailures"
    namespace = "GitLabPi"
    value     = "1"
  }
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failure" {
  alarm_name          = "gitlab-backup-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "GitLabBackupFailures"
  namespace           = "GitLabPi"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors GitLab backup failures"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]

  tags = merge(var.tags, {
    Name    = "GitLab Backup Failure Alarm"
    Purpose = "monitoring"
  })
}
