# Database Backup and Restore - CampusEnroll HA

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
./database/scripts/restore.ps1 -BackupFile ./database/backups/campusenroll_campusenroll_YYYYMMDD_HHMMSS.dump
```

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

## Daily Strategy
- Daily full logical backup (off-peak hours).
- Keep at least 7 daily + 4 weekly backups.
- Run backup integrity checks (`pg_restore --list` and periodic test restore).

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