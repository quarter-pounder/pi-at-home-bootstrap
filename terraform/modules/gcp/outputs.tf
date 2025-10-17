# GCP Module Outputs

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "backup_bucket" {
  description = "GCS bucket name for backups"
  value       = google_storage_bucket.backups.name
  sensitive   = false
}

output "backup_bucket_url" {
  description = "GCS bucket URL for backups"
  value       = "gs://${google_storage_bucket.backups.name}"
  sensitive   = false
}

output "service_account_email" {
  description = "Service account email for Pi authentication"
  value       = google_service_account.pi_service_account.email
  sensitive   = false
}

output "service_account_key" {
  description = "Service account key (base64 encoded)"
  value       = google_service_account_key.pi_key.private_key
  sensitive   = true
}

output "dr_webhook_function_url" {
  description = "Cloud Function URL for DR webhooks"
  value       = google_cloudfunctions2_function.dr_webhook.service_config[0].uri
  sensitive   = false
}

output "pubsub_topic" {
  description = "Pub/Sub topic for DR notifications"
  value       = google_pubsub_topic.dr_notifications.name
  sensitive   = false
}

output "logs_bucket" {
  description = "GCS bucket for logs"
  value       = google_storage_bucket.logs.name
  sensitive   = false
}

output "secret_name" {
  description = "Secret Manager secret name for Pi credentials"
  value       = google_secret_manager_secret.pi_credentials.secret_id
  sensitive   = false
}

output "cloud_scheduler_job" {
  description = "Cloud Scheduler job name for health checks"
  value       = google_cloud_scheduler_job.pi_health_check.name
  sensitive   = false
}
