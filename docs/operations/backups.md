# Backup and Restore

This stack uses [restic](https://restic.net/) for encrypted, deduplicated backups. The workflow is split into two layers: declarative backup profiles (`backup.yml`) and the execution script (`common/scripts/backup.sh`). Make targets wrap the script for direct use.

Available commands:

- `make backup` — manual snapshot (`BACKUP_MODE=manual`)
- `make backup-prune` — snapshot + retention pruning (`BACKUP_MODE=prune`)
- `make backup-cloud` — snapshot to remote storage (`RESTIC_REMOTE` required)

---

## Prerequisites
- `restic`
- **Password file**: Restic requires a stable password. Store it in an ignored file:
  ```bash
  printf 'change-me' > config-registry/env/restic.password
  chmod 600 config-registry/env/restic.password
  ```
> Optional: set `RESTIC_REPOSITORY` in `.env` to override the default local path (`/srv/backups/local`), and/or set `RESTIC_REMOTE` when you want `make backup-cloud` to push off-site.

- **Backup profiles**

`config-registry/env/backup.yml` defines what gets backed up:

  backups:
    full:
      include:
        - /srv/forgejo/data
        - /srv/forgejo-actions-runner
        # ...
      tmp_dumps: /srv/backups/tmp
    cloud:
      include:
        - /srv/forgejo/data
      tmp_dumps: /srv/backups/tmp
  ```
  You can create more profiles or point BACKUP_CONFIG at another file via .env.

- **PostgreSQL credentials for dumps**

For unattended database dumps, create a `.pgpass` file and mount it into the PostgreSQL container:

  ```bash
  sudo install -m 600 -o 999 -g 999 /dev/stdin /srv/postgres/.pgpass <<'EOF'
  *:5432:forgejo:postgres:YOUR_DB_PASSWORD
  EOF
  ```
  Then add the path to `.env`:
  ```bash
  POSTGRES_PGPASS_FILE=/srv/postgres/.pgpass
  ```
  Re-render and redeploy the postgres domain so Docker mounts the file:
  ```bash
  make render DOMAIN=postgres
  make deploy DOMAIN=postgres
  ```

  If `.pgpass` is not present the backup script falls back to reading `POSTGRES_PASSWORD` from the container environment, but the `.pgpass` flow avoids exporting passwords altogether.

## Local Backup Routine
`common/scripts/backup.sh` performs the following:
1. Dumps the Forgejo PostgreSQL database to the configured `tmp_dumps` directory (default `/srv/backups/tmp`), respecting `PG_DUMP_TIMEOUT` (default 300s).
2. Runs `restic backup` with tags `<YYYYMMDD>` and `<BACKUP_MODE>`.
   - `/srv/forgejo/data`
   - `/srv/forgejo-actions-runner`
   - `/srv/adblocker`
   - `/srv/registry`
   - `/srv/monitoring/prometheus`, `/srv/monitoring/alertmanager`, `/srv/monitoring/grafana`
   - the SQL dumps and `config-registry/env/secrets.env.vault`
3. Applies retention (`--keep-daily 7 --keep-weekly 4 --keep-monthly 6`).
4. Removes the temporary SQL dumps.

## Remote Backups
Cloud backups reuse the same script but point the Restic repository at a remote target.

1. **Pick a backend** supported by Restic (S3, Backblaze B2, GCS, etc). Examples:
   - AWS S3 or compatible: `RESTIC_REMOTE=s3:s3.amazonaws.com/pi-forge-backups`
   - Backblaze B2: `RESTIC_REMOTE=b2:pi-forge-backups`
   - Google Cloud Storage: `RESTIC_REMOTE=gs:pi-forge-backups`
2. **Store credentials in `.env`:**
   ```bash
   # Example for S3
   RESTIC_REMOTE=s3:s3.amazonaws.com/pi-forge-backups
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_DEFAULT_REGION=us-east-1

  # Example for GCS
  RESTIC_REMOTE=gs:pi-forge-backups
  GOOGLE_APPLICATION_CREDENTIALS=/path/to/gcloud-service-account.json
   ```
   The `backup`, `backup-prune`, and `backup-cloud` targets load `.env` automatically, so the variables above will be available whenever the commands run.
3. **Understand what gets uploaded:** when `BACKUP_MODE=cloud`, the script limits the payload to Forgejo’s data directory (including the Actions runner state), the freshly generated SQL dumps, and `config-registry/env/secrets.env.vault`. Monitoring volumes, Pi-hole, registry blobs, etc. are omitted to keep cloud usage minimal. You can tune this list in `config-registry/env/backup.yml`.
4. **Initialize the remote repository (first run only):**
   ```bash
   make backup-cloud
   ```
   This runs `restic init` if the repository is empty, performs a Forgejo-only snapshot, and tags it.
5. **Verify snapshots:**
   ```bash
   RESTIC_REPOSITORY="$RESTIC_REMOTE" \
   RESTIC_PASSWORD_FILE=config-registry/env/restic.password \
   restic snapshots
   ```

> **Note:** if `RESTIC_REMOTE` is not set, `make backup-cloud` will exit with `[Backup][err] RESTIC_REMOTE not set (define in .env)` to avoid uploading to the local repository by mistake.

## Restore
Use `common/scripts/restore.sh` to extract a snapshot:
```bash
RESTIC_REPOSITORY=/srv/backups/local \
RESTIC_PASSWORD_FILE=config-registry/env/restic.password \
common/scripts/restore.sh latest /srv/restores/latest
```

After restoring, you can reinstate services by copying the directories back into `/srv` (stopping the relevant containers first) and re-importing SQL dumps into PostgreSQL. Always test restores on a disposable host to validate snapshots.

## Log Rotation
Bootstrap installs `/etc/logrotate.d/pi-forge-backup` to rotate `/var/log/pi-forge-backup.log` daily (7 retained, compressed). Cron examples should direct output to this log:
```cron
0 2 * * * cd /path/to/pi-forge && BACKUP_MODE=cron make backup >> /var/log/pi-forge-backup.log 2>&1
0 3 * * 0 cd /path/to/pi-forge && BACKUP_MODE=prune BACKUP_PRUNE=1 make backup >> /var/log/pi-forge-backup.log 2>&1
30 3 * * * cd /path/to/pi-forge && BACKUP_MODE=cloud make backup-cloud >> /var/log/pi-forge-backup.log 2>&1
```

## Disaster-Recovery Scope
- DR targets focus on Forgejo and its Actions runner; other domains are Pi-specific utilities that can be rebuilt locally if required.
- Goal is rapid restoration of code hosting and CI: replicate PostgreSQL data (Forgejo) and persistent volumes (`/srv/forgejo`, `/srv/forgejo-actions-runner`) to cloud storage, then launch Forgejo plus a runner on demand.
- Proposed landing zone: managed Postgres (e.g. NeonDB), object storage for `/srv/forgejo` and `/srv/forgejo-actions-runner`, and Cloud Run or equivalent container runtime for stateless services. Final design remains pending while the monitoring soak concludes.
- Backups already include Forgejo data and the Actions runner; DR work will layer scheduling, replication, and launch scripts on top of the existing restic routines.
