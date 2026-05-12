#!/usr/bin/env bash
set -euo pipefail

POSTGRES_DB="${POSTGRES_DB:-campusenroll}"
POSTGRES_USER="${POSTGRES_USER:-campus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-55432}"
SCHEMA="${POSTGRES_SCHEMA:-campusenroll}"
OUTPUT_DIR="${OUTPUT_DIR:-./database/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/${POSTGRES_DB}_${SCHEMA}_${TIMESTAMP}.dump"

mkdir -p "$OUTPUT_DIR"

if docker ps --format '{{.Names}}' | grep -q '^campusenroll-postgres$'; then
  echo "[info] using docker exec against campusenroll-postgres"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" campusenroll-postgres \
    pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -n "$SCHEMA" -Fc > "$OUTPUT_FILE"
else
  echo "[info] using network connection to ${POSTGRES_HOST}:${POSTGRES_PORT}"
  PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" -n "$SCHEMA" -Fc -f "$OUTPUT_FILE"
fi

echo "backup generated: $OUTPUT_FILE"