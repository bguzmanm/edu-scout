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

  # Cada reporte es autocontenido (~2 MB): basta con los últimos.
  { ls -1t "$REPORT_DIR"/reporte-*.html 2>/dev/null || true; } |
    tail -n +8 | xargs -r rm -f
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

  # nginx corre como root pero con `cap_drop: ALL`, así que no puede crear el
  # archivo si el directorio pertenece a otro usuario. En ese caso `reopen` no
  # falla de forma visible y nginx sigue escribiendo en el inode ya archivado:
  # el sitio funciona, pero no hay access.log nuevo y la rotación se pierde.
  for _ in 1 2 3 4 5; do
    [ -e "$LOG_FILE" ] && break
    sleep 1
  done

  if [ ! -e "$LOG_FILE" ]; then
    cat >&2 <<EOF

nginx no pudo crear $LOG_FILE después del reopen.

El directorio debe pertenecer a root (nginx pierde CAP_DAC_OVERRIDE por el
cap_drop del compose) y ser escribible por tu grupo, para poder rotar sin sudo:

  sudo chown root:\$(id -un) "$LOG_DIR"
  sudo chmod 775 "$LOG_DIR"
  docker compose -f "$BASE_DIR/docker-compose.app.yml" exec -T nginx nginx -s reopen

Mientras tanto nginx sigue escribiendo en $archive.
EOF
    exit 1
  fi

  echo "Log archivado en $archive"

  # Los archivos rotados no entran en el reporte; se conservan un año por si
  # hay que revisar algo puntual.
  find "$LOG_DIR" -maxdepth 1 -name 'access-*.log' -mtime +365 -delete \
    2>/dev/null || true
fi
