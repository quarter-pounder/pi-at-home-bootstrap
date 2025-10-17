#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

echo "=========================================="
echo "  GCP Terraform Setup (Always Free Tier)  "
echo "=========================================="
echo ""

# Check if GCP is selected
if [[ "${USE_GCP:-true}" != "true" ]]; then
  echo "${YELLOW}Skipping GCP setup (USE_GCP=false)${RESET}"
  exit 0
fi

# Check required variables
required_vars=("GCP_PROJECT_ID" "CLOUDFLARE_API_TOKEN" "DOMAIN" "ALERT_EMAIL")
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "${RED}Missing required variable: $var${RESET}"
    echo "Please set it in your .env file"
    exit 1
  fi
done

echo "[i] Installing Terraform..."
if ! command -v terraform >/dev/null 2>&1; then
  # Install Terraform
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update
  sudo apt install -y terraform
else
  echo "${GREEN}Terraform already installed${RESET}"
fi

echo "[i] Installing Google Cloud SDK..."
if ! command -v gcloud >/dev/null 2>&1; then
  # Install gcloud
  curl https://sdk.cloud.google.com | bash
  source ~/.bashrc
else
  echo "${GREEN}Google Cloud SDK already installed${RESET}"
fi

echo "[i] Setting up GCP authentication..."
# Initialize gcloud
gcloud auth login --no-launch-browser
gcloud config set project "${GCP_PROJECT_ID}"

# Enable required APIs
echo "[i] Enabling GCP APIs..."
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  secretmanager.googleapis.com \
  cloudscheduler.googleapis.com

echo "[i] Creating Terraform configuration..."
cd terraform

# Create terraform.tfvars from environment
cat > terraform.tfvars << EOF
# Generated from .env file
use_gcp = true
gcp_project_id = "${GCP_PROJECT_ID}"
gcp_region = "${GCP_REGION:-us-central1}"
cloudflare_api_token = "${CLOUDFLARE_API_TOKEN}"
domain = "${DOMAIN}"
cloudflare_tunnel_name = "${CLOUDFLARE_TUNNEL_NAME:-gitlab-pi}"
pi5_ip = "${PI5_IP:-}"
grafana_port = ${GRAFANA_PORT:-3000}
alert_email = "${ALERT_EMAIL}"
dr_webhook_url = "${DR_WEBHOOK_URL:-}"
backup_retention_days = ${BACKUP_RETENTION_DAYS:-30}
environment = "prod"
tags = {
  Project = "gitlab-pi"
  ManagedBy = "terraform"
  Environment = "prod"
  CloudProvider = "gcp"
}
EOF

echo "[i] Initializing Terraform..."
terraform init

echo "[i] Planning Terraform deployment..."
terraform plan -out=tfplan

echo ""
echo "${YELLOW}Review the plan above. This will create:${RESET}"
echo "  - GCS bucket for backups (5GB Always Free)"
echo "  - Cloud Functions for DR webhooks (2M invocations/month Always Free)"
echo "  - Cloud Scheduler for health checks (3 jobs Always Free)"
echo "  - Pub/Sub for notifications (10GB/month Always Free)"
echo "  - Cloud Logging for Pi logs (50GB/month Always Free)"
echo "  - Secret Manager for credentials (6 secrets Always Free)"
echo "  - Cloud Monitoring alerts (150GB/month Always Free)"
echo ""

read -p "Continue with deployment? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Deployment cancelled"
  exit 0
fi

echo "[i] Applying Terraform configuration..."
terraform apply tfplan

echo ""
echo "${GREEN}GCP infrastructure deployed successfully!${RESET}"
echo ""

# Get outputs
echo "[i] Retrieving configuration..."
BACKUP_BUCKET=$(terraform output -raw gcp_backup_bucket)
SERVICE_ACCOUNT=$(terraform output -raw gcp_service_account_email)
DR_WEBHOOK_URL=$(terraform output -raw gcp_dr_webhook_url)
PUBSUB_TOPIC=$(terraform output -raw gcp_pubsub_topic)

echo "Generated .env additions:"
echo "========================="
echo "BACKUP_BUCKET=gs://${BACKUP_BUCKET}"
echo "GCP_PROJECT_ID=${GCP_PROJECT_ID}"
echo "GCP_SERVICE_ACCOUNT=${SERVICE_ACCOUNT}"
echo "DR_WEBHOOK_URL=${DR_WEBHOOK_URL}"
echo "GCP_PUBSUB_TOPIC=${PUBSUB_TOPIC}"
echo ""

# Create service account key
echo "[i] Creating service account key..."
gcloud iam service-accounts keys create /tmp/gcp-key.json \
  --iam-account="${SERVICE_ACCOUNT}"

echo "[i] Service account key created: /tmp/gcp-key.json"
echo "${YELLOW}IMPORTANT: Copy this key to your Pi and set GOOGLE_APPLICATION_CREDENTIALS${RESET}"

echo ""
echo "Next steps:"
echo "1. Copy the .env additions above to your Pi's .env file"
echo "2. Copy /tmp/gcp-key.json to your Pi"
echo "3. Set GOOGLE_APPLICATION_CREDENTIALS=/path/to/gcp-key.json on your Pi"
echo "4. Run backup script to test GCS integration"
echo ""

echo "${GREEN}GCP setup complete!${RESET}"
