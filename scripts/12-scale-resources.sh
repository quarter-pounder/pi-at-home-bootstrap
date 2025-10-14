#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "GitLab Resource Scaler"
echo "======================"
echo ""

MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "Detected: ${MEM_GB}GB RAM"
echo ""

echo "Select resource profile:"
echo "  1. Light (4GB RAM)  - Puma: 2 workers, Sidekiq: 5 concurrency"
echo "  2. Medium (8GB RAM) - Puma: 2 workers, Sidekiq: 10 concurrency [CURRENT]"
echo "  3. Heavy (8GB RAM)  - Puma: 3 workers, Sidekiq: 15 concurrency"
echo "  4. Custom"
echo ""
read -p "Choose [1-4]: " -r choice

case $choice in
  1)
    PUMA_WORKERS=2
    PUMA_THREADS=2
    SIDEKIQ_CONCURRENCY=5
    PG_SHARED_BUFFERS="256MB"
    ;;
  2)
    PUMA_WORKERS=2
    PUMA_THREADS=2
    SIDEKIQ_CONCURRENCY=10
    PG_SHARED_BUFFERS="256MB"
    ;;
  3)
    PUMA_WORKERS=3
    PUMA_THREADS=4
    SIDEKIQ_CONCURRENCY=15
    PG_SHARED_BUFFERS="512MB"
    ;;
  4)
    read -p "Puma workers [2]: " PUMA_WORKERS
    PUMA_WORKERS=${PUMA_WORKERS:-2}
    read -p "Puma threads [2]: " PUMA_THREADS
    PUMA_THREADS=${PUMA_THREADS:-2}
    read -p "Sidekiq concurrency [10]: " SIDEKIQ_CONCURRENCY
    SIDEKIQ_CONCURRENCY=${SIDEKIQ_CONCURRENCY:-10}
    read -p "PostgreSQL shared_buffers [256MB]: " PG_SHARED_BUFFERS
    PG_SHARED_BUFFERS=${PG_SHARED_BUFFERS:-256MB}
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "${YELLOW}Creating backup of current config...${RESET}"
if [[ -f compose/gitlab.rb ]]; then
  cp compose/gitlab.rb compose/gitlab.rb.backup.$(date +%s)
fi

echo "${YELLOW}Updating GitLab configuration...${RESET}"

cat > compose/gitlab.rb <<EOF
external_url '${GITLAB_EXTERNAL_URL}'
gitlab_rails['gitlab_shell_ssh_port'] = 2222

nginx['listen_port'] = 80
nginx['listen_https'] = false

gitlab_rails['time_zone'] = '${TIMEZONE}'
gitlab_rails['initial_root_password'] = '${GITLAB_ROOT_PASSWORD}'

gitlab_rails['gitlab_email_enabled'] = true
gitlab_rails['gitlab_email_from'] = 'gitlab@${DOMAIN}'
gitlab_rails['gitlab_email_display_name'] = 'GitLab'
gitlab_rails['gitlab_email_reply_to'] = 'noreply@${DOMAIN}'

gitlab_rails['smtp_enable'] = false

gitlab_rails['registry_enabled'] = true
gitlab_rails['registry_host'] = 'registry.${DOMAIN}'
gitlab_rails['registry_port'] = '5050'
registry_external_url 'https://registry.${DOMAIN}'
registry_nginx['listen_port'] = 5050
registry_nginx['listen_https'] = false

gitlab_rails['backup_keep_time'] = 604800

puma['worker_processes'] = ${PUMA_WORKERS}
puma['min_threads'] = 1
puma['max_threads'] = ${PUMA_THREADS}

sidekiq['max_concurrency'] = ${SIDEKIQ_CONCURRENCY}

postgresql['shared_buffers'] = "${PG_SHARED_BUFFERS}"
postgresql['max_worker_processes'] = 4

prometheus_monitoring['enable'] = true
grafana['enable'] = false

gitlab_rails['env'] = {
  'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000'
}
EOF

echo ""
echo "${YELLOW}Restarting GitLab...${RESET}"
cd compose
docker compose -f gitlab.yml restart gitlab

echo ""
echo "${GREEN}Configuration updated!${RESET}"
echo ""
echo "New settings:"
echo "  Puma workers: ${PUMA_WORKERS}"
echo "  Puma threads: ${PUMA_THREADS}"
echo "  Sidekiq concurrency: ${SIDEKIQ_CONCURRENCY}"
echo "  PostgreSQL shared_buffers: ${PG_SHARED_BUFFERS}"
echo ""
echo "GitLab is restarting. This may take 2-3 minutes."
echo "Monitor with: docker logs -f gitlab"

