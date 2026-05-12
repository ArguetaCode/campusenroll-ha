#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: ./database/scripts/restore.sh <backup_file.dump>"
  exit 1
fi

BACKUP_FILE="$1"
POSTGRES_DB="${POSTGRES_DB:-campusenroll}"
POSTGRES_USER="${POSTGRES_USER:-campus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-55432}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "backup file not found: $BACKUP_FILE"
  exit 1
fi

if docker ps --format '{{.Names}}' | grep -q '^campusenroll-postgres$'; then
  echo "[info] restoring with docker exec (clean in target schema objects only)"
  cat "$BACKUP_FILE" | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" campusenroll-postgres \
    pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges
else
  echo "[info] restoring over network connection"
  PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges "$BACKUP_FILE"
fi

echo "restore completed from: $BACKUP_FILE"