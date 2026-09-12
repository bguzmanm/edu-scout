#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$DEPLOY_DIR"
docker compose -f "$DEPLOY_DIR/docker-compose.prod.yml" pull
docker compose -f "$DEPLOY_DIR/docker-compose.prod.yml" up -d