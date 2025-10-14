#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "GitLab LFS Configuration"
echo "========================"
echo ""

echo "${YELLOW}Configuring GitLab for Git LFS...${RESET}"

if [[ ! -f compose/gitlab.rb ]]; then
  echo "GitLab config not found. Run setup-gitlab first."
  exit 1
fi

if grep -q "lfs_enabled" compose/gitlab.rb; then
  echo "LFS already configured in GitLab."
else
  echo "Adding LFS configuration..."

  cat >> compose/gitlab.rb <<'EOF'

# Git LFS Configuration
gitlab_rails['lfs_enabled'] = true
gitlab_rails['lfs_storage_path'] = "/var/opt/gitlab/gitlab-rails/shared/lfs-objects"
EOF
fi

echo ""
echo "${YELLOW}Creating LFS storage directory...${RESET}"
sudo mkdir -p /srv/gitlab/data/git-data/lfs-objects
sudo chown -R $(id -u):$(id -g) /srv/gitlab/data/git-data/lfs-objects

echo ""
echo "${YELLOW}Restarting GitLab...${RESET}"
cd compose
docker compose -f gitlab.yml restart gitlab

echo ""
echo "${GREEN}LFS configuration complete!${RESET}"
echo ""
echo "To use LFS in a repository:"
echo "  1. Install git-lfs client: apt install git-lfs"
echo "  2. In your repo: git lfs install"
echo "  3. Track files: git lfs track '*.psd'"
echo "  4. Commit .gitattributes: git add .gitattributes"
echo "  5. Push normally"
echo ""
echo "Verify in GitLab: Settings → Repository → Git Large File Storage"

