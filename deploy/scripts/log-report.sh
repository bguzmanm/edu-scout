#!/usr/bin/env bash
#
# Reporte de tráfico a partir del access log de nginx.
#
# Uso (en la VM eduscout-app, desde el directorio deploy/):
#   ./scripts/log-report.sh            # dashboard interactivo en la terminal
#   ./scripts/log-report.sh --html     # reporte HTML autocontenido
#   ./scripts/log-report.sh --rotate   # archiva el log actual y empieza de cero
#
# goaccess corre en un contenedor efímero, así que no hay nada que instalar en
# la VM. Los reportes quedan en deploy/logs/reportes/.
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs/nginx"
REPORT_DIR="$BASE_DIR/logs/reportes"
LOG_FILE="$LOG_DIR/access.log"
GOACCESS_IMAGE="${GOACCESS_IMAGE:-allinurl/goaccess:latest}"

usage() {
  cat <<'EOF'
Uso: log-report.sh [--html] [--rotate]

  (sin opciones)  Dashboard interactivo en la terminal.
  --html          Genera un reporte HTML y muestra su ruta.
  --rotate        Después de reportar, archiva access.log y reabre el log.

Variables:
  GOACCESS_IMAGE  Imagen de goaccess a usar (por defecto allinurl/goaccess:latest).
EOF
}

generate_html=0
rotate=0

for arg in "$@"; do
  case "$arg" in
    --html) generate_html=1 ;;
    --rotate) rotate=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -s "$LOG_FILE" ]; then
  cat >&2 <<EOF
Todavía no hay accesos en $LOG_FILE

Si el sitio ya recibe visitas, es probable que nginx siga corriendo con la
configuración anterior. Aplica el cambio y vuelve a intentar:

  cd "$BASE_DIR"
  docker compose -f docker-compose.app.yml up -d nginx
EOF
  exit 1
fi

mkdir -p "$REPORT_DIR" 2>/dev/null || {
  cat >&2 <<EOF
No se pudo crear $REPORT_DIR

Los directorios de deploy/logs pertenecen a root (Docker los crea así). Corre el
script con sudo, o devuélvelos a tu usuario:

  sudo chown -R "\$(id -un)" /opt/eduscout/deploy/logs
EOF
  exit 1
}

GOACCESS_ARGS=(
  /logs/access.log
  --log-format=COMBINED
  --ignore-crawlers
  --no-global-config
)

# Salida no interactiva (o --html): reporte HTML estático.
if [ "$generate_html" -eq 1 ] || [ ! -t 1 ]; then
  stamp="$(date +%Y%m%d-%H%M)"
  target="/reportes/reporte-$stamp.html"
  docker run --rm \
    -v "$LOG_DIR:/logs:ro" \
    -v "$REPORT_DIR:/reportes" \
    "$GOACCESS_IMAGE" \
    "${GOACCESS_ARGS[@]}" \
    --html-prefs='{"theme":"bright","numQueries":10}' \
    -o "$target"

  cp "$REPORT_DIR/reporte-$stamp.html" "$REPORT_DIR/ultimo.html"
  echo "Reporte HTML: $REPORT_DIR/reporte-$stamp.html"
  echo "Copia del último: $REPORT_DIR/ultimo.html"
else
  docker run --rm -it \
    -v "$LOG_DIR:/logs:ro" \
    -v "$REPORT_DIR:/reportes" \
    "$GOACCESS_IMAGE" \
    "${GOACCESS_ARGS[@]}"
fi

if [ "$rotate" -eq 1 ]; then
  archive="$LOG_DIR/access-$(date +%Y%m%d-%H%M).log"
  mv "$LOG_FILE" "$archive"
  # USR1: nginx reabre sus archivos de log y crea el access.log nuevo.
  docker compose -f "$BASE_DIR/docker-compose.app.yml" exec -T nginx nginx -s reopen
  echo "Log archivado en $archive"
fi
