#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/opt/eduscout/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date +%F_%H%M)"
FILE="$BACKUP_DIR/eduscout_$STAMP.sql.gz"

cd "$DEPLOY_DIR"
set -a
# shellcheck disable=SC1091
. "$DEPLOY_DIR/.env"
set +a

mkdir -p "$BACKUP_DIR"
docker compose -f "$DEPLOY_DIR/docker-compose.db.yml" exec -T db \
  pg_dump -U "${DATABASE_USER:-eduscout}" "${DATABASE_NAME:-eduscout}" | gzip > "$FILE"
echo "backup: $FILE"

find "$BACKUP_DIR" -name 'eduscout_*.sql.gz' -mtime "+$RETENTION_DAYS" -delete