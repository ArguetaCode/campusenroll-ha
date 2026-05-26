# Database Backup and Restore - CampusEnroll HA

Important: a backup that has not been restored successfully in a drill does not count as real recovery capability.

## Variables
Use environment variables instead of hardcoding secrets:
- `POSTGRES_DB` (default `campusenroll`)
- `POSTGRES_USER` (default `campus`)
- `POSTGRES_PASSWORD` (no default in scripts)
- `POSTGRES_HOST` (default `127.0.0.1`)
- `POSTGRES_PORT` (default `55432`)
- `POSTGRES_SCHEMA` (default `campusenroll`)

## Backup
Linux/macOS:
```bash
export POSTGRES_PASSWORD='***'
./database/scripts/backup.sh
```

Windows PowerShell:
```powershell
$env:POSTGRES_PASSWORD='***'
./database/scripts/backup.ps1
```

## Restore
Linux/macOS:
```bash
export POSTGRES_PASSWORD='***'
./database/scripts/restore.sh ./database/backups/campusenroll_campusenroll_YYYYMMDD_HHMMSS.dump
```

Windows PowerShell:
```powershell
$env:POSTGRES_PASSWORD='***'
./database/scripts/restore.ps1 -BackupFile ./database/backups/campusenroll_campusenroll_YYYYMMDD_HHMMSS.dump -ConfirmRestore
```

`-ConfirmRestore` is required because restore is destructive for the target database: the script uses `pg_restore --clean --if-exists`. Use it only against an isolated restore target or an explicitly approved non-production database.

The PowerShell restore script prints the target mode, database, user, and backup file before restoring. It is still not a production restore automation tool.

## Restore Test Procedure
1. Create backup from current state.
2. Restore into an isolated PostgreSQL instance (recommended) or non-production environment.
3. Validate object counts in key tables (`students`, `courses`, `enrollments`, `payments`, `notifications`).
4. Execute smoke tests against services.

## RPO and RTO
- RPO (Recovery Point Objective): maximum acceptable data loss time window.
- RTO (Recovery Time Objective): maximum acceptable time to restore service.

Suggested starting targets:
- RPO: 15-60 minutes (depends on backup/WAL strategy).
- RTO: 30-120 minutes (depends on automation and environment size).

For the current project state, these are targets, not proven guarantees. The current logical dump scripts alone are closer to daily/manual recovery unless scheduled backups and WAL/PITR are implemented.

## Daily Strategy
- Daily full logical backup (off-peak hours).
- Keep at least 7 daily + 4 weekly backups.
- Run backup integrity checks (`pg_restore --list` and periodic test restore).
- Copy backups outside the database host. At minimum, keep one encrypted copy on another LAN machine or durable object storage.
- Protect backup files from accidental deletion and ransomware where possible.

## Suggested Retention

- Daily logical backups: keep 7.
- Weekly logical backups: keep 4.
- Pre-deployment backups: keep at least until the next successful deployment and restore drill.
- WAL archives: retain long enough to cover the agreed PITR window.

## Restore Drill

Run a restore drill regularly, and always before claiming the environment is recoverable:

1. Create a fresh backup.
2. Restore into an isolated PostgreSQL instance, not the active database.
3. Validate Flyway history:

```bash
docker exec <restore-postgres> psql -U campus -d campusenroll -c "SELECT installed_rank, version, description, success FROM campusenroll.flyway_schema_history ORDER BY installed_rank;"
```

4. Validate core table counts:

```bash
docker exec <restore-postgres> psql -U campus -d campusenroll -c "SELECT 'students' AS table_name, count(*) FROM campusenroll.students UNION ALL SELECT 'courses', count(*) FROM campusenroll.courses UNION ALL SELECT 'enrollments', count(*) FROM campusenroll.enrollments UNION ALL SELECT 'payments', count(*) FROM campusenroll.payments UNION ALL SELECT 'notifications', count(*) FROM campusenroll.notifications;"
```

5. Point a disposable app stack at the restored database.
6. Run `scripts/gateway-smoke-ci.ps1`.
7. Record restore duration, backup file name, PostgreSQL version, and issues found.

## Before Deployments
- Always create a pre-deployment backup.
- Apply migrations only after backup is confirmed.
- Keep rollback runbook documented.

## Production Recommendations
- Store backups encrypted at rest and in transit.
- Replicate backups to a second region/account.
- Protect backup retention with immutable storage policies where possible.

## WAL Archiving
- Enable WAL archiving in production to reduce RPO beyond daily dumps.
- Store WAL files in durable object storage.
- Monitor archive lag and failures.

## Point-In-Time Recovery (PITR)
- Combine periodic base backups + WAL archive.
- Rebuild a new instance and replay WAL to target timestamp.
- Document timeline selection and test PITR quarterly.

## Read Replica
- Use streaming replication for read workloads and DR readiness.
- Keep writes strictly on primary.

## PostgreSQL HA Lab Backup

The PostgreSQL HA lab has separate backup and restore drill scripts. These target only lab containers:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-backup.ps1
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-restore-drill.ps1 -BackupFile .\database\postgres-ha-lab\backups\<file>.dump -ConfirmRestoreDrill
```

The restore drill uses an ephemeral container and does not restore into `campusenroll-postgres`, `postgres-primary-lab`, or `postgres-replica-lab`.

HA lab scripts are explicitly marked `LAB ONLY / NOT FOR PRODUCTION`. Destructive lab scripts require confirmation flags and print the exact containers/volumes they can touch.

After a lab promotion, use the post-promotion rebuild script if you need to preserve the promoted lab data before recreating primary/replica:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-rebuild-replica-after-promotion.ps1 -ConfirmDestroyLab
```
