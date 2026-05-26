# PostgreSQL Replication Plan - CampusEnroll HA

Detailed lab runbook: `docs/postgresql-ha-lab.md`.

Current status: a separated laboratory primary/replica setup exists in `docker-compose.postgres-ha-lab.yml`. It is not an implemented production HA setup and is not wired into the default application stack.

## Current Lab Topology
- Primary: accepts all writes and authoritative transactions.
- Read Replica: asynchronous replica for read-heavy queries and reporting.

This topology is for technical learning and controlled validation only. Default CampusEnroll services continue using `campusenroll-postgres` unless an operator manually changes environment variables for a lab experiment.

## Read/Write Routing
Read from replica (candidate use cases):
- analytics dashboards
- historical reports
- non-critical list endpoints with eventual consistency tolerance

Write to primary always:
- enrollment creation/status changes
- payment state transitions
- notification persistence/idempotency

## Replication Lag Risks
- Stale reads may show outdated status.
- Read-after-write consistency is not guaranteed on replica.
- Critical workflows should pin reads to primary after writes.

## Failover
Manual failover (lab recommendation):
1. Detect primary failure.
2. Promote replica.
3. Repoint application connection strings.
4. Validate write path and replication health.

Lab command:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-promote-replica.ps1 -ConfirmPromoteLab
```

Promotion breaks the original lab topology. Rebuild the replica after promotion.

Post-promotion recovery runbook:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-rebuild-replica-after-promotion.ps1 -ConfirmDestroyLab
```

See `docs/postgresql-ha-lab-post-promotion.md` for split-brain risks and recovery options.

Automatic failover (future):
- Evaluate Patroni + etcd/Consul.
- Add fencing and split-brain safeguards.

## PgBouncer (Future Only)
Use PgBouncer in front of PostgreSQL for:
- connection pooling
- reduced backend connection churn
- improved throughput during bursts

## Monitoring Replication (Future Only)
Track at minimum:
- `pg_stat_replication` lag bytes/time
- replica replay delay
- WAL generation rate
- replication slot health
- failover alerts and promotion events

Prometheus + Grafana do not currently prove PostgreSQL production HA. Replication dashboards and alert rules are future work.

## Application Integration Plan

Current services should keep using the existing local database unless a specific lab test changes their environment manually.

Future write connection variables for the lab primary:

```env
DB_HOST=<lab-primary-host>
DB_PORT=55433
DB_NAME=campusenroll_lab
DB_USER=campus_lab
DB_PASSWORD=campus_lab123
```

Do not point write services at `55434`; that is the replica and should reject writes while in recovery.
