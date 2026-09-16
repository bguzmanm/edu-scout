#!/usr/bin/env bash
set -euo pipefail

# Backup cifrado de PostgreSQL (pg_dump + gzip + gpg AES256).
# Corre en la VM eduscout-db vía docker compose (socket local, sin password).
#
# Requisito: gnupg instalado en la VM db (sudo apt-get install -y gnupg).
# Passphrase: archivo $GPG_PASSPHRASE_FILE (chmod 600), independiente del .env
# para no exponer el resto de secretos al shell.
#
# Descifrar:
#   gpg --batch --decrypt --pinentry-mode loopback --passphrase-file pass \
#       --output backup.sql.gz eduscout_YYYY-MM-DD_HHMM.sql.gz.gpg
#   gunzip backup.sql.gz

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/opt/eduscout/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
GPG_PASSPHRASE_FILE="${GPG_PASSPHRASE_FILE:-$DEPLOY_DIR/.backup-gpg-passphrase}"
STAMP="$(date +%F_%H%M)"
FILE="$BACKUP_DIR/eduscout_$STAMP.sql.gz.gpg"

if [ ! -r "$GPG_PASSPHRASE_FILE" ]; then
  echo "error: falta el archivo de passphrase $GPG_PASSPHRASE_FILE (chmod 600)" >&2
  exit 1
fi
if ! command -v gpg >/dev/null 2>&1; then
  echo "error: gnupg no está instalado" >&2
  exit 1
fi

export PGCLIENTENCODING=UTF8

mkdir -p "$BACKUP_DIR"
docker compose -f "$DEPLOY_DIR/docker-compose.db.yml" exec -T db \
  pg_dump -U "${DATABASE_USER:-eduscout}" "${DATABASE_NAME:-eduscout}" \
  | gzip \
  | gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase-file "$GPG_PASSPHRASE_FILE" \
        --symmetric --cipher-algo AES256 -o "$FILE"

echo "backup (cifrado): $FILE"

find "$BACKUP_DIR" -name 'eduscout_*.sql.gz.gpg' -mtime "+$RETENTION_DAYS" -delete