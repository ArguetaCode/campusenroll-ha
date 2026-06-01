#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: ./scripts/patroni/restore-emergency-on-pc4.sh <backup_file.dump>"
  exit 1
fi

BACKUP_FILE="$1"
POSTGRES_DB="${POSTGRES_DB:-campusenroll}"
POSTGRES_USER="${POSTGRES_USER:-campus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-campus123}"
EMERGENCY_PORT="${EMERGENCY_PORT:-55432}"
CONTAINER_NAME="${CONTAINER_NAME:-campusenroll-postgres-emergency}"
VOLUME_NAME="${VOLUME_NAME:-campusenroll_postgres_emergency_data}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "backup file not found: $BACKUP_FILE"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[restore] starting emergency PostgreSQL on port ${EMERGENCY_PORT}"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -e POSTGRES_DB="$POSTGRES_DB" \
    -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    -p "${EMERGENCY_PORT}:5432" \
    -v "${VOLUME_NAME}:/var/lib/postgresql/data" \
    postgres:16
fi

echo "[restore] waiting for emergency PostgreSQL"
until docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
  pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  sleep 2
done

echo "[restore] restoring $BACKUP_FILE"
docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$BACKUP_FILE"

echo "[restore] emergency database ready at 192.168.0.13:${EMERGENCY_PORT}"
echo "[restore] point microservices temporarily to jdbc:postgresql://192.168.0.13:${EMERGENCY_PORT}/${POSTGRES_DB}"
