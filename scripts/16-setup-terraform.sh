#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up cloud infrastructure with Terraform..."

# Check if Terraform is installed
if ! command -v terraform >/dev/null 2>&1; then
  echo "[!] Terraform is not installed. Installing..."

  # Detect OS and architecture
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
  esac

  # Download and install Terraform
  TERRAFORM_VERSION="1.6.6"
  wget -O terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
  unzip terraform.zip
  sudo mv terraform /usr/local/bin/
  rm terraform.zip

  echo "[i] Terraform installed successfully"
fi

# Check if terraform.tfvars exists
if [[ ! -f terraform/terraform.tfvars ]]; then
  echo "[!] terraform.tfvars not found. Creating from example..."
  cp terraform/terraform.tfvars.example terraform/terraform.tfvars

  echo ""
  echo "Please edit terraform/terraform.tfvars with your values:"
  echo "  - cloudflare_api_token"
  echo "  - domain"
  echo "  - pi5_ip (optional)"
  echo "  - alert_email (optional)"
  echo ""
  read -p "Press Enter after editing terraform.tfvars..."
fi

# Initialize Terraform
echo "[i] Initializing Terraform..."
cd terraform
terraform init

# Plan deployment
echo "[i] Planning Terraform deployment..."
terraform plan

# Ask for confirmation
echo ""
read -p "Apply Terraform configuration? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Terraform deployment cancelled"
  exit 0
fi

# Apply configuration
echo "[i] Applying Terraform configuration..."
terraform apply -auto-approve

# Get outputs and update .env
echo "[i] Updating .env with Terraform outputs..."

# Get Cloudflare tunnel token
TUNNEL_TOKEN=$(terraform output -raw cloudflare_tunnel_token)
if [[ -n "$TUNNEL_TOKEN" ]]; then
  if grep -q "CLOUDFLARE_TUNNEL_TOKEN=" ../.env; then
    sed -i "s/CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL_TOKEN/" ../.env
  else
    echo "CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL_TOKEN" >> ../.env
  fi
fi

# Get S3 bucket name
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
if [[ -n "$BUCKET_NAME" ]]; then
  if grep -q "BACKUP_BUCKET=" ../.env; then
    sed -i "s|BACKUP_BUCKET=.*|BACKUP_BUCKET=s3://$BUCKET_NAME|" ../.env
  else
    echo "BACKUP_BUCKET=s3://$BUCKET_NAME" >> ../.env
  fi
fi

# Get AWS credentials
AWS_ACCESS_KEY=$(terraform output -raw aws_access_key_id)
AWS_SECRET_KEY=$(terraform output -raw aws_secret_access_key)

if [[ -n "$AWS_ACCESS_KEY" && -n "$AWS_SECRET_KEY" ]]; then
  if grep -q "AWS_ACCESS_KEY_ID=" ../.env; then
    sed -i "s/AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY/" ../.env
  else
    echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY" >> ../.env
  fi

  if grep -q "AWS_SECRET_ACCESS_KEY=" ../.env; then
    sed -i "s/AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY/" ../.env
  else
    echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY" >> ../.env
  fi
fi

echo ""
echo "Terraform setup complete!"
echo ""
echo "Resources created:"
echo "  - Cloudflare tunnel: $(terraform output -raw cloudflare_tunnel_id)"
echo "  - S3 bucket: $BUCKET_NAME"
echo "  - DNS records: $(terraform output -json dns_records | jq -r 'to_entries[] | "\(.key): \(.value)"')"
echo ""
echo "Your .env file has been updated with the new values."
echo "You can now run: ./scripts/07-setup-cloudflare-tunnel.sh"
