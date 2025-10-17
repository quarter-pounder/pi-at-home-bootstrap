# Terraform Configuration

Terraform configurations for managing cloud resources used by the GitLab Pi setup.

## Cloud Providers

### GCP (Recommended - Better Always Free Tier)
- **Cloud Storage**: 5GB Always Free
- **Cloud Functions**: 2M invocations/month Always Free
- **Cloud Scheduler**: 3 jobs Always Free
- **Pub/Sub**: 10GB/month Always Free
- **Cloud Logging**: 50GB/month Always Free
- **Secret Manager**: 6 secrets Always Free
- **Cloud Monitoring**: 150GB/month Always Free

### AWS (Alternative)
- **S3**: 5GB Always Free (first 12 months)
- **SNS**: 1M requests/month Always Free
- **CloudWatch**: 10 custom metrics Always Free

## Overview

The Terraform configuration manages:
- **Cloudflare**: DNS records and tunnel configuration
- **GCP/AWS**: Cloud storage for backups, monitoring, and DR automation

## Prerequisites

1. **Terraform**: Install [Terraform](https://terraform.io/downloads) >= 1.0
2. **Cloudflare API Token**: Create a token with Zone:Read and Zone:Edit permissions
3. **GCP Project** (recommended): Create a GCP project and enable billing
4. **AWS Credentials** (alternative): Configure AWS CLI or environment variables

## Quick Start

1. **Choose your cloud provider:**
   ```bash
   # For GCP (recommended)
   cp terraform-gcp.tfvars.example terraform.tfvars

   # For AWS (alternative)
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars with your values:**
   ```bash
   vim terraform.tfvars
   ```

3. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan
   ```

5. **Apply the configuration:**
   ```bash
   terraform apply
   ```

6. **Get the outputs for your .env file:**
   ```bash
   terraform output -json env_variables
   ```

## Configuration

### Required Variables

- `cloudflare_api_token`: Cloudflare API token
- `domain`: Domain name (e.g., "example.com")

### Optional Variables

- `pi5_ip`: IP address of your Pi 5 (leave empty to use tunnel CNAMEs)
- `alert_email`: Email for backup failure alerts
- `backup_retention_days`: How long to keep backups (default: 30 days)

## Resources Created

### Cloudflare
- **Tunnel**: Secure connection to your Pi 5
- **DNS Records**: A records or CNAMEs for gitlab, registry, grafana subdomains
- **Tunnel Configuration**: Routes traffic to your Pi services

### GCP
- **Cloud Storage**: Encrypted backup storage with lifecycle policies
- **Service Account**: Dedicated account for backup operations
- **Cloud Functions**: DR webhook processing
- **Cloud Scheduler**: Health check automation
- **Pub/Sub**: DR notifications
- **Cloud Logging**: Centralized log aggregation
- **Secret Manager**: Secure credential storage
- **Cloud Monitoring**: Alerting and metrics

### AWS
- **S3 Bucket**: Encrypted backup storage with lifecycle policies
- **IAM User**: Dedicated user for backup operations
- **SNS Topic**: Email alerts for backup failures
- **CloudWatch**: Log groups and alarms for monitoring

## Integration with Pi Setup

After running `terraform apply`, you'll get outputs that can be added to your `.env` file:

```bash
# For GCP (recommended)
CLOUDFLARE_TUNNEL_TOKEN="your-tunnel-token"
BACKUP_BUCKET="gs://your-bucket-name"
GCP_PROJECT_ID="your-project-id"
GCP_SERVICE_ACCOUNT="your-service-account@project.iam.gserviceaccount.com"
DR_WEBHOOK_URL="https://your-function-url"

# For AWS (alternative)
CLOUDFLARE_TUNNEL_TOKEN="your-tunnel-token"
BACKUP_BUCKET="s3://your-bucket-name"
AWS_ACCESS_KEY_ID="your-access-key"
AWS_SECRET_ACCESS_KEY="your-secret-key"
```

## Updating Resources

To update your cloud resources:

```bash
# Modify terraform.tfvars or .tf files
vim terraform.tfvars

# Plan changes
terraform plan

# Apply changes
terraform apply
```

## Destroying Resources

To remove all cloud resources:

```bash
terraform destroy
```

**Warning**: This will delete your S3 bucket and all backups!

## Troubleshooting

### Common Issues

1. **Cloudflare API Token**: Ensure it has the correct permissions
2. **AWS Credentials**: Verify your AWS configuration
3. **Domain Ownership**: Make sure you own the domain in Cloudflare

### Getting Help

- Check Terraform logs: `terraform apply -auto-approve`
- Validate configuration: `terraform validate`
- Check state: `terraform show`

## Security Notes

- S3 bucket is encrypted and private
- IAM user has minimal required permissions
- Cloudflare tunnel provides secure access
- All sensitive outputs are marked as sensitive
