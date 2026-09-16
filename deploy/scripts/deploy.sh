#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-app}"

case "$TARGET" in
  app)
    COMPOSE="$DEPLOY_DIR/docker-compose.app.yml"
    ;;
  db)
    COMPOSE="$DEPLOY_DIR/docker-compose.db.yml"
    ;;
  *)
    echo "Uso: $0 {app|db}" >&2
    exit 2
    ;;
esac

cd "$DEPLOY_DIR"
docker compose -f "$COMPOSE" pull
docker compose -f "$COMPOSE" up -d