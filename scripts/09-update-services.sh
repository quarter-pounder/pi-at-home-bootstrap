#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "Updating GitLab and monitoring services..."
echo ""

backup_first() {
  echo "${YELLOW}[!] Creating backup before update...${RESET}"
  ./backup/backup.sh
  echo ""
}

update_gitlab() {
  echo "${YELLOW}Updating GitLab...${RESET}"
  cd compose

  docker compose -f gitlab.yml pull
  docker compose -f gitlab.yml up -d

  echo "Waiting for GitLab to restart..."
  sleep 30

  if docker exec gitlab gitlab-rake gitlab:check SANITIZE=true >/dev/null 2>&1; then
    echo "${GREEN}✓ GitLab updated successfully${RESET}"
  else
    echo "${YELLOW}⚠ GitLab may need more time to start. Check: docker logs gitlab${RESET}"
  fi
  cd ..
}

update_monitoring() {
  echo ""
  echo "${YELLOW}Updating monitoring stack...${RESET}"
  cd compose

  docker compose -f monitoring.yml pull
  docker compose -f monitoring.yml up -d

  echo "${GREEN}✓ Monitoring stack updated${RESET}"
  cd ..
}

update_system() {
  echo ""
  echo "${YELLOW}Updating system packages...${RESET}"
  sudo apt update
  sudo apt upgrade -y
  sudo apt autoremove -y
  echo "${GREEN}✓ System packages updated${RESET}"
}

echo "Update options:"
echo "  1. GitLab only"
echo "  2. Monitoring only"
echo "  3. System packages only"
echo "  4. Everything (recommended)"
echo ""
read -p "Choose [1-4]: " -r choice

case $choice in
  1)
    backup_first
    update_gitlab
    ;;
  2)
    update_monitoring
    ;;
  3)
    update_system
    ;;
  4)
    backup_first
    update_gitlab
    update_monitoring
    update_system
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "${GREEN}✓ Update complete!${RESET}"
echo "Run health check: ./scripts/08-health-check.sh"

