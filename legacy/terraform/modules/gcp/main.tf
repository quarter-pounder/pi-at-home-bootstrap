# GCP Module - Cloud Infrastructure for Pi at Home Bootstrap
# Uses GCP Always Free Tier resources

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# GCP Project
data "google_project" "current" {
  project_id = var.project_id
}

# Cloud Storage Bucket for backups
resource "google_storage_bucket" "backups" {
  name          = "${var.project_id}-pi-backups"
  location      = var.region
  force_destroy = true

  # Always Free Tier: 5GB storage, 1GB egress per month
  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

# Service Account for Pi to access GCP
resource "google_service_account" "pi_service_account" {
  account_id   = "pi-backup-service"
  display_name = "Pi Backup Service Account"
  description  = "Service account for Pi to upload backups to GCP"
}

# IAM binding for service account to access storage
resource "google_project_iam_member" "pi_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.pi_service_account.email}"
}

# Service Account Key for Pi authentication
resource "google_service_account_key" "pi_key" {
  service_account_id = google_service_account.pi_service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Cloud Functions for DR webhook processing (Always Free Tier: 2M invocations/month)
resource "google_cloudfunctions2_function" "dr_webhook" {
  name        = "pi-dr-webhook"
  location    = var.region
  description = "Process DR webhooks from Pi"

  build_config {
    runtime     = "python311"
    entry_point = "process_webhook"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.dr_webhook_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "128M"
    timeout_seconds    = 60
    environment_variables = {
      WEBHOOK_URL = var.dr_webhook_url
    }
  }
}

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "functions_source" {
  name     = "${var.project_id}-functions-source"
  location = var.region
}

# Cloud Function source code
resource "google_storage_bucket_object" "dr_webhook_source" {
  name   = "dr-webhook.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.dr_webhook_source.output_path
}

# Archive the Cloud Function source
data "archive_file" "dr_webhook_source" {
  type        = "zip"
  output_path = "/tmp/dr-webhook.zip"
  source {
    content = templatefile("${path.module}/dr-webhook.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
}

# Cloud Scheduler for periodic health checks (Always Free Tier: 3 jobs)
resource "google_cloud_scheduler_job" "pi_health_check" {
  name        = "pi-health-check"
  description = "Periodic health check for Pi system"
  schedule    = "*/5 * * * *" # Every 5 minutes
  time_zone   = "UTC"

  http_target {
    http_method = "GET"
    uri         = "https://${var.pi_domain}/api/health"
    headers = {
      "User-Agent" = "GCP-Health-Check"
    }
  }
}

# Cloud Logging for Pi logs (Always Free Tier: 50GB/month)
resource "google_logging_project_sink" "pi_logs" {
  name        = "pi-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.logs.name}"
  filter      = "resource.type=\"gce_instance\" AND labels.\"pi-system\"=\"true\""
}

# Storage bucket for logs
resource "google_storage_bucket" "logs" {
  name          = "${var.project_id}-pi-logs"
  location      = var.region
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 30 # Keep logs for 30 days
    }
    action {
      type = "Delete"
    }
  }
}

# IAM for log sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_logging_project_sink.pi_logs.writer_identity}"
}

# Pub/Sub topic for DR notifications (Always Free Tier: 10GB/month)
resource "google_pubsub_topic" "dr_notifications" {
  name = "pi-dr-notifications"
}

# Pub/Sub subscription
resource "google_pubsub_subscription" "dr_notifications" {
  name  = "pi-dr-notifications-sub"
  topic = google_pubsub_topic.dr_notifications.name

  # Always Free Tier: 10GB/month
  message_retention_duration = "600s"
  ack_deadline_seconds       = 20
}

# Cloud Monitoring for Pi metrics (Always Free Tier: 150GB/month)
resource "google_monitoring_notification_channel" "email" {
  display_name = "Email Notifications"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

# Alerting policy for Pi down
resource "google_monitoring_alert_policy" "pi_down" {
  display_name = "Pi System Down"
  combiner     = "OR"
  conditions {
    display_name = "Pi health check failing"
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"pi-dr-webhook\""
      duration       = "300s"
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 1
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }
}

# Secret Manager for sensitive data (Always Free Tier: 6 secrets)
resource "google_secret_manager_secret" "pi_credentials" {
  secret_id = "pi-credentials"
  replication {
    auto {}
  }
}

# Secret version with service account key
resource "google_secret_manager_secret_version" "pi_credentials" {
  secret      = google_secret_manager_secret.pi_credentials.id
  secret_data = base64decode(google_service_account_key.pi_key.private_key)
}

# IAM for secret access
resource "google_secret_manager_secret_iam_member" "pi_secret_access" {
  secret_id = google_secret_manager_secret.pi_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pi_service_account.email}"
}
