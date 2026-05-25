#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${POSTGRES_REPLICATION_USER:-}" || -z "${POSTGRES_REPLICATION_PASSWORD:-}" ]]; then
  echo "[primary-lab] POSTGRES_REPLICATION_USER and POSTGRES_REPLICATION_PASSWORD are required"
  exit 1
fi

echo "[primary-lab] configuring replication access for lab network"
cat >> "$PGDATA/pg_hba.conf" <<EOF

# CampusEnroll HA lab replication. Lab-only; do not copy blindly to production.
host replication ${POSTGRES_REPLICATION_USER} 0.0.0.0/0 scram-sha-256
host replication ${POSTGRES_REPLICATION_USER} ::/0 scram-sha-256
EOF

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${POSTGRES_REPLICATION_USER}') THEN
      CREATE ROLE ${POSTGRES_REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${POSTGRES_REPLICATION_PASSWORD}';
   ELSE
      ALTER ROLE ${POSTGRES_REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${POSTGRES_REPLICATION_PASSWORD}';
   END IF;
END
\$\$;
SQL

echo "[primary-lab] replication user ready"
