#!/usr/bin/env bash
set -euo pipefail

# Endurece la VM eduscout-db: PostgreSQL (5432) solo alcanzable desde el
# CIDR interno de la VCN (10.0.0.0/16). Todo lo demás se descarta de INPUT.
# Idempotente: se puede reejecutar sin duplicar reglas.
#
# Aplicar vía SSH a la VM eduscout-db:
#   rsync/ssh upload + sudo bash deploy/scripts/harden-db-iptables.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "error: ejecutar como root (sudo)" >&2
  exit 1
fi

if ! command -v iptables >/dev/null 2>&1; then
  echo "error: iptables no instalado" >&2
  exit 1
fi

INTERNAL_CIDR="10.0.0.0/16"
PORT="5432"

# Limpia reglas previas del script para ser idempotente
iptables -D INPUT -p tcp --dport "$PORT" -s "$INTERNAL_CIDR" -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport "$PORT" -j DROP 2>/dev/null || true

iptables -A INPUT -p tcp --dport "$PORT" -s "$INTERNAL_CIDR" -j ACCEPT
iptables -A INPUT -p tcp --dport "$PORT" -j DROP

echo "Reglas aplicadas: $PORT aceptado solo desde $INTERNAL_CIDR."

# Persistencia entre reinicios
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
  echo "Cambios persistidos con netfilter-persistent."
elif [ -d /etc/iptables ]; then
  iptables-save > /etc/iptables/rules.v4
  echo "Reglas guardadas en /etc/iptables/rules.v4 (revisar iptables-persistent)."
else
  echo "ADVERTENCIA: no se detectó netfilter-persistent; instala iptables-persistent para sobrevivir reinicios."
  exit 1
fi

echo "Verificación: iptables -L INPUT -n --line-numbers (filtrar por $PORT)."