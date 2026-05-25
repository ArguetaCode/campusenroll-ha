param(
    [switch]$ConfirmDestroyLab
)

$ErrorActionPreference = "Stop"

if (-not $ConfirmDestroyLab) {
    throw "This destroys only PostgreSQL HA lab containers/volumes. Re-run with -ConfirmDestroyLab to reset the lab topology."
}

$labContainers = @(
    "postgres-primary-lab",
    "postgres-replica-lab",
    "postgres-restore-drill-lab"
)

$labVolumes = @(
    "campusenroll_postgres_primary_lab_data",
    "campusenroll_postgres_replica_lab_data",
    "campusenroll_postgres_primary_lab_wal_archive"
)

$protectedContainers = @("campusenroll-postgres")
$protectedVolumes = @("campusenroll-ha_campusenroll_pg_data", "campusenroll_pg_data")

Write-Host "CampusEnroll PostgreSQL HA Lab - reset" -ForegroundColor Yellow
Write-Warning "This removes lab containers and lab volumes only. It does not use docker compose down -v."

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

Write-Host "Lab reset completed. You can run postgres-ha-lab-up.ps1 to recreate primary/replica." -ForegroundColor Green
