#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ATTEMPT=0
while :; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[$ATTEMPT] $(date '+%F %T') terraform apply -auto-approve"
  if terraform apply -auto-approve; then
    echo "[$ATTEMPT] OK"
    terraform output
    break
  fi
  echo "[$ATTEMPT] sin capacidad, reintento en 15 min"
  sleep 900
done