#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <backup_name>"
  echo ""
  echo "Available local backups:"
  ls -1 "${BACKUP_DIR}/gitlab/" | grep -oP 'gitlab-backup-\d{8}_\d{6}' | sort -u
  echo ""
  if [[ -n "${BACKUP_BUCKET:-}" ]]; then
    echo "Available S3 backups:"
    docker run --rm \
      -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
      -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
      amazon/aws-cli s3 ls "${BACKUP_BUCKET}/" | awk '{print $2}'
  fi
  exit 1
fi

BACKUP_NAME=$1
LOCAL_BACKUP_DIR="${BACKUP_DIR}/gitlab"

if [[ ! -f "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_gitlab_backup.tar" ]]; then
  if [[ -n "${BACKUP_BUCKET:-}" ]]; then
    echo "[i] Backup not found locally, downloading from S3..."
    mkdir -p "${LOCAL_BACKUP_DIR}"
    docker run --rm \
      -v "${LOCAL_BACKUP_DIR}:/backup" \
      -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
      -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
      amazon/aws-cli s3 sync "${BACKUP_BUCKET}/${BACKUP_NAME}/" /backup/
  else
    echo "[!] Backup not found: ${BACKUP_NAME}"
    exit 1
  fi
fi

echo "[!] WARNING: This will restore GitLab to backup: ${BACKUP_NAME}"
echo "[!] All current data will be replaced!"
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Restore cancelled"
  exit 1
fi

echo "[i] Stopping GitLab services..."
cd compose
docker compose -f gitlab.yml stop
docker compose -f monitoring.yml stop

echo "[i] Restoring GitLab configuration..."
tar -xzf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_config.tar.gz" -C /srv/gitlab/

echo "[i] Copying backup to container..."
docker cp "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_gitlab_backup.tar" gitlab:/var/opt/gitlab/backups/

echo "[i] Starting GitLab for restore..."
docker compose -f gitlab.yml start gitlab

echo "[i] Waiting for GitLab to start..."
sleep 30

echo "[i] Restoring GitLab data..."
docker exec gitlab gitlab-backup restore BACKUP=${BACKUP_NAME} force=yes

echo "[i] Restoring runner configuration..."
tar -xzf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_runner.tar.gz" -C /srv/gitlab-runner/

echo "[i] Restoring registry data..."
tar -xzf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_registry.tar.gz" -C /srv/registry/

if [[ -f "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_prometheus.tar.gz" ]]; then
  echo "[i] Restoring Prometheus data..."
  tar -xzf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_prometheus.tar.gz" -C /srv/prometheus/
fi

if [[ -f "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_grafana.tar.gz" ]]; then
  echo "[i] Restoring Grafana data..."
  tar -xzf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_grafana.tar.gz" -C /srv/grafana/
fi

echo "[i] Restarting all services..."
docker compose -f gitlab.yml restart
docker compose -f monitoring.yml restart

echo "[i] Restore complete!"
echo "[i] Please verify all services are running correctly"

