#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="gitlab-backup-${TIMESTAMP}"
LOCAL_BACKUP_DIR="${BACKUP_DIR}/gitlab"

echo "[i] Starting GitLab backup..."

mkdir -p "${LOCAL_BACKUP_DIR}"

echo "[i] Creating GitLab application backup..."
docker exec gitlab gitlab-backup create BACKUP=${BACKUP_NAME}

echo "[i] Copying backup files from container..."
docker cp gitlab:/var/opt/gitlab/backups/${BACKUP_NAME}_gitlab_backup.tar "${LOCAL_BACKUP_DIR}/"

echo "[i] Backing up GitLab configuration..."
tar -czf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_config.tar.gz" -C /srv/gitlab config/

echo "[i] Backing up runner configuration..."
tar -czf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_runner.tar.gz" -C /srv/gitlab-runner config/

echo "[i] Backing up registry data..."
tar -czf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_registry.tar.gz" -C /srv/registry .

echo "[i] Backing up monitoring data..."
tar -czf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_prometheus.tar.gz" -C /srv/prometheus . 2>/dev/null || true
tar -czf "${LOCAL_BACKUP_DIR}/${BACKUP_NAME}_grafana.tar.gz" -C /srv/grafana . 2>/dev/null || true

if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${BACKUP_BUCKET:-}" ]]; then
  echo "[i] Syncing to S3..."
  docker run --rm \
    -v "${LOCAL_BACKUP_DIR}:/backup" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    amazon/aws-cli s3 sync /backup "${BACKUP_BUCKET}/${BACKUP_NAME}/"

  echo "[i] Cleaning up old S3 backups..."
  CUTOFF_DATE=$(date -d "${BACKUP_RETENTION_DAYS:-7} days ago" +%Y%m%d)
  docker run --rm \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    amazon/aws-cli s3 ls "${BACKUP_BUCKET}/" | \
    awk '{print $2}' | \
    grep -E '^gitlab-backup-[0-9]{8}' | \
    while read -r backup; do
      backup_date=$(echo "$backup" | grep -oP '\d{8}')
      if [[ "$backup_date" -lt "$CUTOFF_DATE" ]]; then
        echo "[i] Deleting old backup: $backup"
        docker run --rm \
          -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
          -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
          amazon/aws-cli s3 rm --recursive "${BACKUP_BUCKET}/${backup}"
      fi
    done
else
  echo "[i] S3 not configured, keeping local backup only"
fi

echo "[i] Cleaning up old local backups..."
find "${BACKUP_DIR}/gitlab" -name "gitlab-backup-*" -type f -mtime +${BACKUP_RETENTION_DAYS:-7} -delete

echo "[i] Backup complete: ${BACKUP_NAME}"
ls -lh "${LOCAL_BACKUP_DIR}"/

