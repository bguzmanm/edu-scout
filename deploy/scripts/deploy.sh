#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(dirname "$DEPLOY_DIR")"
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

# git como root sobre un checkout de ubuntu: sin esto git rechaza el repo por
# "dubious ownership" (el servicio systemd corre como root).
repo_git() {
  git -C "$REPO_DIR" -c safe.directory="$REPO_DIR" "$@"
}

# Sincroniza los archivos de infraestructura con origin/main. /opt/eduscout es un
# checkout del repo público, así que nginx.conf, los compose y los scripts se
# actualizan solos en cada corrida del timer. Lo no versionado (.env,
# .backup-gpg-passphrase, terraform.tfstate, logs/) no se toca.
sync_repo() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Aviso: $REPO_DIR no es un checkout de git; se despliega la copia local." >&2
    return 0
  fi

  if repo_git fetch --quiet origin main 2>/dev/null; then
    repo_git reset --hard --quiet FETCH_HEAD
    echo "Repositorio sincronizado: $(repo_git rev-parse --short HEAD)"
  else
    echo "Aviso: no se pudo sincronizar con origin; se despliega $(repo_git rev-parse --short HEAD)." >&2
  fi
}

# Docker crea los directorios del bind mount como root; se devuelven al dueño del
# repo para poder generar reportes y rotar el access log sin sudo.
prepare_logs() {
  [ "$TARGET" = "app" ] || return 0

  mkdir -p "$DEPLOY_DIR/logs/nginx" "$DEPLOY_DIR/logs/reportes"
  local owner
  owner="$(stat -c %U "$DEPLOY_DIR")"
  if [ "$(id -u)" -eq 0 ] && [ "$owner" != "root" ]; then
    chown "$owner" \
      "$DEPLOY_DIR/logs" \
      "$DEPLOY_DIR/logs/nginx" \
      "$DEPLOY_DIR/logs/reportes"
  fi
  chmod 775 \
    "$DEPLOY_DIR/logs" \
    "$DEPLOY_DIR/logs/nginx" \
    "$DEPLOY_DIR/logs/reportes"
}

sync_repo
prepare_logs

cd "$DEPLOY_DIR"
docker compose -f "$COMPOSE" pull
docker compose -f "$COMPOSE" up -d

# nginx lee su configuración del archivo montado: un cambio en nginx.conf no
# recrea el contenedor por sí solo, así que hay que recargarlo. nginx valida
# antes de aplicar; si la config es inválida mantiene la anterior y el servicio
# falla, dejando el error en el journal.
if [ "$TARGET" = "app" ] &&
  docker compose -f "$COMPOSE" ps --services --status running | grep -qx nginx; then
  docker compose -f "$COMPOSE" exec -T nginx nginx -s reload
  echo "nginx recargado con la configuración del repositorio"
fi
