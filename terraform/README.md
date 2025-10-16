# Terraform Configuration

Terraform configurations for managing cloud resources used by the GitLab Pi setup.

## Overview

The Terraform configuration manages:
- **Cloudflare**: DNS records and tunnel configuration
- **AWS**: S3 backup bucket, IAM users, monitoring, and alerting

## Prerequisites

1. **Terraform**: Install [Terraform](https://terraform.io/downloads) >= 1.0
2. **Cloudflare API Token**: Create a token with Zone:Read and Zone:Edit permissions
3. **AWS Credentials**: Configure AWS CLI or environment variables

## Quick Start

1. **Copy the example variables file:**
   ```bash
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

### AWS
- **S3 Bucket**: Encrypted backup storage with lifecycle policies
- **IAM User**: Dedicated user for backup operations
- **SNS Topic**: Email alerts for backup failures
- **CloudWatch**: Log groups and alarms for monitoring

## Integration with Pi Setup

After running `terraform apply`, you'll get outputs that can be added to your `.env` file:

```bash
# Add these to your .env file
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
