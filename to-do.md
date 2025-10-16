# Disaster Recovery Design - Free Tier

## Overview

This document outlines a cost-effective disaster recovery solution that stays within free tier limits of major cloud providers while providing automated failover capabilities.

## Architecture

```
Pi 5 (Primary)                    Cloud (Standby)
├── GitLab CE                    ├── GitLab CE (minimal)
├── Prometheus                   ├── Prometheus (minimal)
├── Grafana                      ├── Grafana (minimal)
├── Loki + Alloy                 ├── Loki + Alloy (minimal)
└── Heartbeat Monitor            └── Webhook Receiver
     │                                 │
     └── S3 Backup Bucket ─────────────┘
```

## Free Tier Resources

### AWS Free Tier
- **EC2 t2.micro**: 750 hours/month (1 instance)
- **S3**: 5GB storage, 20,000 GET requests, 2,000 PUT requests
- **Lambda**: 1M requests, 400,000 GB-seconds
- **CloudWatch**: 10 custom metrics, 1GB log ingestion
- **Route 53**: 1 hosted zone

### Google Cloud Free Tier
- **Compute Engine**: 1 f1-micro instance (30 days)
- **Cloud Storage**: 5GB storage, 1GB egress
- **Cloud Functions**: 2M invocations, 400,000 GB-seconds
- **Cloud Monitoring**: 150MB logs, 10 custom metrics

### Oracle Cloud Free Tier
- **Compute**: 2 ARM-based VMs (1GB RAM each)
- **Object Storage**: 20GB storage, 20GB egress
- **Functions**: 2M invocations, 400,000 GB-seconds

## Implementation Strategy

### Phase 1: Backup Infrastructure

#### S3 Backup Strategy
```bash
# Enhanced backup script with S3 sync
#!/bin/bash
BACKUP_BUCKET="gitlab-pi-backups"
REGION="us-east-1"

# Create backup
docker exec gitlab gitlab-backup create

# Sync to S3
aws s3 sync /srv/gitlab/data/ s3://$BACKUP_BUCKET/gitlab/ \
  --storage-class STANDARD_IA \
  --delete

# Sync configuration
aws s3 sync /srv/gitlab/config/ s3://$BACKUP_BUCKET/config/ \
  --storage-class STANDARD_IA
```

#### Backup Retention
- **Local**: 7 days (SD card)
- **S3**: 30 days (Standard-IA)
- **S3 Glacier**: 90 days (for long-term)

### Phase 2: Heartbeat Monitoring

#### Prometheus Alert Rule
```yaml
# config/prometheus-alerts.yml
groups:
  - name: disaster_recovery
    rules:
      - alert: Pi5Down
        expr: up{job="node-exporter"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Pi 5 is down, activating DR"
          description: "Pi 5 has been down for 2 minutes"
        webhook_configs:
          - url: "https://your-webhook-url.com/activate-dr"
            send_resolved: true
```

#### Webhook Handler (Lambda/Cloud Function)
```python
import json
import boto3
import subprocess

def lambda_handler(event, context):
    # Parse webhook payload
    alert = json.loads(event['body'])

    if alert['status'] == 'firing':
        # Activate DR instance
        activate_dr_instance()

        # Sync data from S3
        sync_from_s3()

        # Update DNS
        update_dns_to_dr()

    return {'statusCode': 200}
```

### Phase 3: DR Instance Management

#### Terraform Configuration
```hcl
# terraform/dr-instance.tf
resource "aws_instance" "gitlab_dr" {
  ami           = "ami-0c02fb55956c7d316"  # Ubuntu 24.04 LTS
  instance_type = "t2.micro"

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    gitlab_domain = var.gitlab_domain
    backup_bucket = var.backup_bucket
  }))

  tags = {
    Name = "gitlab-dr"
    Environment = "disaster-recovery"
  }
}

# Auto-shutdown when not needed
resource "aws_cloudwatch_metric_alarm" "dr_shutdown" {
  alarm_name          = "dr-shutdown"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "Shutdown DR instance when not needed"
  alarm_actions       = [aws_sns_topic.dr_shutdown.arn]
}
```

#### DR Instance User Data
```bash
#!/bin/bash
# user-data.sh for DR instance

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install AWS CLI
apt-get update
apt-get install -y awscli

# Create directories
mkdir -p /srv/gitlab/{data,logs,config}
mkdir -p /srv/prometheus
mkdir -p /srv/grafana
mkdir -p /srv/loki

# Download and restore from S3
aws s3 sync s3://${backup_bucket}/gitlab/ /srv/gitlab/data/
aws s3 sync s3://${backup_bucket}/config/ /srv/gitlab/config/

# Start minimal services
docker compose -f /opt/gitlab-dr/docker-compose.yml up -d

# Health check endpoint
echo '#!/bin/bash
curl -f http://localhost:80/-/health || exit 1' > /usr/local/bin/health-check
chmod +x /usr/local/bin/health-check
```

### Phase 4: Automated Failover

#### DNS Management
```python
# dns_manager.py
import boto3

def update_dns_to_dr():
    route53 = boto3.client('route53')

    # Update A record to point to DR instance
    route53.change_resource_record_sets(
        HostedZoneId='Z1234567890',
        ChangeBatch={
            'Changes': [{
                'Action': 'UPSERT',
                'ResourceRecordSet': {
                    'Name': 'gitlab.yourdomain.com',
                    'Type': 'A',
                    'TTL': 300,
                    'ResourceRecords': [{'Value': 'DR_INSTANCE_IP'}]
                }
            }]
        }
    )
```

#### Data Sync Strategy
```bash
#!/bin/bash
# sync_from_s3.sh

# Stop services
docker compose down

# Sync data from S3
aws s3 sync s3://$BACKUP_BUCKET/gitlab/ /srv/gitlab/data/
aws s3 sync s3://$BACKUP_BUCKET/config/ /srv/gitlab/config/

# Start services
docker compose up -d

# Wait for health check
while ! curl -f http://localhost:80/-/health; do
  sleep 10
done

# Notify that DR is active
curl -X POST https://your-webhook-url.com/dr-active
```

## Cost Optimization

### Resource Scheduling
- **DR Instance**: Only running during failover
- **S3 Storage**: Use Standard-IA for cost savings
- **Lambda**: Pay-per-use for webhook handling
- **CloudWatch**: Minimal metrics to stay within free tier

### Monitoring Costs
```bash
# Cost monitoring script
#!/bin/bash
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

## Recovery Procedures

### Automatic Recovery
1. **Detection**: Prometheus alert triggers webhook
2. **Activation**: Lambda starts DR instance
3. **Sync**: Data synced from S3
4. **DNS**: Route53 updated to DR instance
5. **Health Check**: Verify services are running

### Manual Recovery
1. **Pi 5 Recovery**: Fix hardware/software issues
2. **Data Sync**: Sync from DR back to Pi 5
3. **DNS Switch**: Route53 back to Pi 5
4. **DR Shutdown**: Terminate DR instance
5. **Verification**: Full health check

### Data Consistency
- **Last Write Wins**: Simple conflict resolution
- **Backup Verification**: Checksums for data integrity
- **Log Preservation**: All logs stored in S3

## Testing

### Monthly DR Test
```bash
#!/bin/bash
# test-dr.sh

# Trigger test failover
curl -X POST https://your-webhook-url.com/test-failover

# Wait for activation
sleep 300

# Verify services
curl -f https://gitlab.yourdomain.com/-/health

# Restore to Pi 5
curl -X POST https://your-webhook-url.com/restore-primary
```

### Automated Testing
- **Weekly**: Health check of DR instance
- **Monthly**: Full failover test
- **Quarterly**: Data integrity verification

## Monitoring and Alerting

### Key Metrics
- **Pi 5 Health**: CPU, memory, disk, temperature
- **DR Instance**: Status, cost, data freshness
- **S3 Backup**: Size, age, integrity
- **DNS**: Resolution time, TTL

### Alert Channels
- **Email**: Critical alerts
- **Slack**: Status updates
- **SMS**: Emergency notifications

## Security Considerations

### Access Control
- **IAM Roles**: Least privilege for DR resources
- **S3 Encryption**: Server-side encryption enabled
- **VPC**: Isolated network for DR instance
- **Secrets**: AWS Secrets Manager for sensitive data

### Backup Security
- **Encryption**: All backups encrypted at rest
- **Access Logging**: S3 access logs enabled
- **Versioning**: S3 versioning for data protection
- **MFA**: Multi-factor authentication for admin access

## Implementation Timeline

### Week 1-2: Foundation
- [ ] Set up S3 backup bucket
- [ ] Implement enhanced backup script
- [ ] Create Lambda webhook handler

### Week 3-4: DR Infrastructure
- [ ] Deploy DR instance with Terraform
- [ ] Implement data sync procedures
- [ ] Set up DNS management

### Week 5-6: Automation
- [ ] Complete failover automation
- [ ] Implement monitoring and alerting
- [ ] Create testing procedures

### Week 7-8: Testing and Optimization
- [ ] Conduct full DR test
- [ ] Optimize costs and performance
- [ ] Document procedures

## Maintenance

### Daily
- Monitor backup status
- Check Pi 5 health
- Review cost metrics

### Weekly
- Test DR instance startup
- Verify S3 backup integrity
- Review alert logs

### Monthly
- Full DR failover test
- Cost analysis and optimization
- Security review

## Conclusion

This disaster recovery solution provides:
- **Cost-effective**: Stays within free tier limits
- **Automated**: Minimal manual intervention
- **Reliable**: Multiple backup layers
- **Scalable**: Can grow with requirements

The solution balances cost, complexity, and reliability to provide enterprise-grade disaster recovery for a home lab setup.
