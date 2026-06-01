#!/usr/bin/env bash
set -euo pipefail

POSTGRES_HOST="${POSTGRES_HOST:-192.168.0.13}"
POSTGRES_PORT="${POSTGRES_PORT:-5000}"
POSTGRES_DB="${POSTGRES_DB:-campusenroll}"
POSTGRES_USER="${POSTGRES_USER:-campus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-campus123}"
EMERGENCY_HOST="${EMERGENCY_HOST:-192.168.0.13}"
EMERGENCY_USER="${EMERGENCY_USER:-$USER}"
REMOTE_DIR="${REMOTE_DIR:-~/campusenroll-emergency-backups}"
OUTPUT_DIR="${OUTPUT_DIR:-./database/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/${POSTGRES_DB}_patroni_${TIMESTAMP}.dump"

mkdir -p "$OUTPUT_DIR"

echo "[backup] dumping ${POSTGRES_DB} from ${POSTGRES_HOST}:${POSTGRES_PORT}"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" -Fc -f "$OUTPUT_FILE"

echo "[backup] generated $OUTPUT_FILE"

if [[ "${COPY_TO_EMERGENCY_NODE:-true}" == "true" ]]; then
  echo "[backup] copying to ${EMERGENCY_USER}@${EMERGENCY_HOST}:${REMOTE_DIR}"
  ssh "${EMERGENCY_USER}@${EMERGENCY_HOST}" "mkdir -p ${REMOTE_DIR}"
  scp "$OUTPUT_FILE" "${EMERGENCY_USER}@${EMERGENCY_HOST}:${REMOTE_DIR}/"
fi
