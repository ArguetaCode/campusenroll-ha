# PostgreSQL Replication Plan - CampusEnroll HA

## Topology
- Primary: accepts all writes and authoritative transactions.
- Read Replica: asynchronous replica for read-heavy queries and reporting.

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
Manual failover (current recommendation):
1. Detect primary failure.
2. Promote replica.
3. Repoint application connection strings.
4. Validate write path and replication health.

Automatic failover (future):
- Evaluate Patroni + etcd/Consul.
- Add fencing and split-brain safeguards.

## PgBouncer
Use PgBouncer in front of PostgreSQL for:
- connection pooling
- reduced backend connection churn
- improved throughput during bursts

## Monitoring Replication
Track at minimum:
- `pg_stat_replication` lag bytes/time
- replica replay delay
- WAL generation rate
- replication slot health
- failover alerts and promotion events

Prometheus + Grafana should include replication dashboards and alert rules.