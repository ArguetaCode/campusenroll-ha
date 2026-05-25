# PostgreSQL HA Lab Post-Promotion Runbook

This runbook explains what to do after manually promoting `postgres-replica-lab` in the CampusEnroll-HA PostgreSQL laboratory.

## What Promotion Means

Promotion turns a standby replica into a writable PostgreSQL primary. After promotion:

- `postgres-replica-lab` is no longer a replica.
- `pg_is_in_recovery()` returns `false` on the promoted node.
- The promoted node accepts writes.
- The old `postgres-primary-lab` must not be started again as if nothing happened.

## Why the Original Topology Is Broken

Before promotion:

```text
postgres-primary-lab  ->  postgres-replica-lab
```

After promotion:

```text
old postgres-primary-lab stopped
postgres-replica-lab promoted and writable
```

The old primary and the promoted replica now represent competing timelines. Restarting the old primary without rebuilding can create split brain: two writable databases that both believe they are primary.

## Post-Promotion Options

Option 1: reset the whole lab.

- Removes lab containers and lab volumes.
- Starts a fresh empty primary/replica topology.
- Safest when lab data does not matter.

Option 2: rebuild from the promoted primary.

- Backs up the promoted `postgres-replica-lab`.
- Removes only lab containers and lab volumes.
- Starts a fresh primary/replica topology using the original names.
- Restores the post-promotion backup into the new `postgres-primary-lab`.
- Lets the fresh `postgres-replica-lab` receive the restored data through streaming replication.

For this lab, option 2 is automated by:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-rebuild-replica-after-promotion.ps1 -ConfirmDestroyLab
```

If the promoted replica is not running, the script falls back to creating a fresh empty topology and says so clearly.

## Safety Guarantees

The rebuild script:

- Requires `-ConfirmDestroyLab`.
- Does not use `docker compose down -v`.
- Removes only allowlisted lab containers:
  - `postgres-primary-lab`
  - `postgres-replica-lab`
  - `postgres-restore-drill-lab`
- Removes only allowlisted lab volumes:
  - `campusenroll_postgres_primary_lab_data`
  - `campusenroll_postgres_replica_lab_data`
  - `campusenroll_postgres_primary_lab_wal_archive`
- Refuses to include protected names such as `campusenroll-postgres` and `campusenroll-ha_campusenroll_pg_data`.

## Validate Current Post-Promotion State

```powershell
docker ps -a --filter "name=postgres-primary-lab" --filter "name=postgres-replica-lab" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker exec postgres-replica-lab psql -U campus_lab -d campusenroll_lab -tAc "SELECT pg_is_in_recovery();"
```

Expected after promotion:

- `postgres-primary-lab`: stopped or absent.
- `postgres-replica-lab`: running.
- `pg_is_in_recovery()` on `postgres-replica-lab`: `f`.

Test that promoted replica accepts writes:

```powershell
docker exec postgres-replica-lab psql -U campus_lab -d campusenroll_lab -c "CREATE SCHEMA IF NOT EXISTS ha_lab; CREATE TABLE IF NOT EXISTS ha_lab.post_promotion_write_probe(id text PRIMARY KEY, created_at timestamptz DEFAULT now()); INSERT INTO ha_lab.post_promotion_write_probe(id) VALUES ('manual-check-' || extract(epoch from now())::text);"
```

## Rebuild Clean Primary/Replica Topology

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-rebuild-replica-after-promotion.ps1 -ConfirmDestroyLab
```

Then validate:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-status.ps1
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-check-replication.ps1
```

Expected clean state:

- `postgres-primary-lab`: running, `pg_is_in_recovery() = f`.
- `postgres-replica-lab`: running, `pg_is_in_recovery() = t`.
- `pg_stat_replication` on primary shows a streaming replica.
- Writes to primary replicate to replica.
- Direct writes to replica fail.

## Lab vs Production

This runbook is lab-only. Production needs:

- automated failover with fencing,
- split-brain prevention,
- durable WAL archive and PITR,
- monitoring/alerting,
- tested restore runbooks,
- secrets management,
- TLS/network hardening.

The lab proves mechanics. It does not prove production HA.
