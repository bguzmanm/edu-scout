#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEPLOY_DIR"

docker compose -f "$DEPLOY_DIR/docker-compose.app.yml" run --rm certbot renew --webroot -w /var/www/certbot --quiet
docker compose -f "$DEPLOY_DIR/docker-compose.app.yml" exec nginx nginx -s reload