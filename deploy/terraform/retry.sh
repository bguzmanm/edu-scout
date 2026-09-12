#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Configuraciones a probar en cada intento (ocpus/memory_in_gbs). Se alterna la shape
# chica (1 OCPU / 6 GB, mejor disponibilidad) con la shape objetivo (2 OCPU / 12 GB).
# La shape efectivamente creada queda determinada por el estado de Terraform.
SIZES=( "1 6" "2 12" )
ATTEMPT=0
while :; do
  ATTEMPT=$((ATTEMPT + 1))
  i=$(( (ATTEMPT - 1) % ${#SIZES[@]} ))
  read -r OCPS MEM <<< "${SIZES[$i]}"
  echo "[$ATTEMPT] $(date '+%F %T') terraform apply -auto-approve (${OCPS} OCPU / ${MEM} GB)"
  if terraform apply -auto-approve -var="ocpus=${OCPS}" -var="memory_in_gbs=${MEM}"; then
    echo "[$ATTEMPT] OK (${OCPS} OCPU / ${MEM} GB)"
    terraform output
    break
  fi
  echo "[$ATTEMPT] sin capacidad, reintento en 15 min"
  sleep 900
done