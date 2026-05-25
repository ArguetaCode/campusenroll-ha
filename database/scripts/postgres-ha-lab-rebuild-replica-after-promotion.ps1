param(
    [string]$ComposeFile = "docker-compose.postgres-ha-lab.yml",
    [string]$BackupDir = "./database/postgres-ha-lab/backups",
    [string]$Database = $env:POSTGRES_LAB_DB,
    [string]$User = $env:POSTGRES_LAB_USER,
    [switch]$ConfirmDestroyLab
)

$ErrorActionPreference = "Stop"

if (-not $Database) { $Database = "campusenroll_lab" }
if (-not $User) { $User = "campus_lab" }

if (-not $ConfirmDestroyLab) {
    throw "This rebuilds the HA lab after promotion by removing lab-only containers/volumes. Re-run with -ConfirmDestroyLab to proceed."
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

$protectedContainers = @("campusenroll-postgres")
$protectedVolumes = @("campusenroll-ha_campusenroll_pg_data", "campusenroll_pg_data")
$labContainers = @("postgres-primary-lab", "postgres-replica-lab", "postgres-restore-drill-lab")
$labVolumes = @(
    "campusenroll_postgres_primary_lab_data",
    "campusenroll_postgres_replica_lab_data",
    "campusenroll_postgres_primary_lab_wal_archive"
)

foreach ($container in $protectedContainers) {
    if ($labContainers -contains $container) {
        throw "Safety check failed: lab container allowlist includes protected container $container."
    }
}

foreach ($volume in $protectedVolumes) {
    if ($labVolumes -contains $volume) {
        throw "Safety check failed: lab volume allowlist includes protected volume $volume."
    }
}

function Invoke-LabCompose {
    param([string[]]$ComposeArgs)
    $env:COMPOSE_IGNORE_ORPHANS = "true"
    & docker compose -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose lab command failed: $($ComposeArgs -join ' ')"
    }
}

function Remove-LabContainersAndVolumes {
    foreach ($container in $labContainers) {
        $exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $container }
        if ($exists) {
            Write-Host "Removing lab container: $container"
            docker rm -f $container | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove lab container: $container"
            }
        }
    }

    foreach ($volume in $labVolumes) {
        $exists = docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $volume }
        if ($exists) {
            Write-Host "Removing lab volume: $volume"
            docker volume rm $volume | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove lab volume: $volume"
            }
        }
    }
}

Write-Host "CampusEnroll PostgreSQL HA Lab - rebuild after promotion" -ForegroundColor Yellow
Write-Warning "This affects only PostgreSQL HA lab containers/volumes. It does not use docker compose down -v."

$promotedReplicaExists = docker ps --format "{{.Names}}" | Where-Object { $_ -eq "postgres-replica-lab" }
$backupFile = $null

if ($promotedReplicaExists) {
    $recovery = (docker exec postgres-replica-lab psql -U $User -d $Database -tAc "SELECT pg_is_in_recovery();" 2>$null).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect postgres-replica-lab. Is it healthy and using database $Database?"
    }

    if ($recovery -ne "f") {
        throw "postgres-replica-lab is not promoted. Expected pg_is_in_recovery() = false, got '$recovery'. Use postgres-ha-lab-check-replication.ps1 for a normal topology."
    }

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path $BackupDir ("post_promotion_{0}_{1}.dump" -f $Database, $timestamp)
    $containerDump = "/tmp/post_promotion_${Database}_${timestamp}.dump"

    Write-Host "Backing up promoted postgres-replica-lab before rebuilding: $backupFile"
    docker exec postgres-replica-lab pg_dump -U $User -d $Database -Fc -f $containerDump
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create backup from promoted replica."
    }

    docker cp "postgres-replica-lab:${containerDump}" $backupFile
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy post-promotion backup from container."
    }

    docker exec postgres-replica-lab rm -f $containerDump | Out-Null
} else {
    Write-Warning "postgres-replica-lab is not running. Rebuilding an empty fresh lab topology."
}

Remove-LabContainersAndVolumes

Write-Host "Starting fresh primary/replica lab topology..."
Invoke-LabCompose -ComposeArgs @("config", "--quiet")
Invoke-LabCompose -ComposeArgs @("up", "-d", "postgres-primary-lab", "postgres-replica-lab")

if ($backupFile) {
    Write-Host "Restoring post-promotion backup into fresh primary. This data will stream to the new replica."
    docker cp $backupFile "postgres-primary-lab:/tmp/post_promotion_restore.dump"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy post-promotion backup into fresh primary."
    }

    docker exec postgres-primary-lab pg_restore -U $User -d $Database --clean --if-exists --no-owner --no-privileges /tmp/post_promotion_restore.dump
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restore post-promotion backup into fresh primary."
    }

    docker exec postgres-primary-lab rm -f /tmp/post_promotion_restore.dump | Out-Null
}

Write-Host "Rebuild completed. Run postgres-ha-lab-check-replication.ps1 to validate the clean topology." -ForegroundColor Green
