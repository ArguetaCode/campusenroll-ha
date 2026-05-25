param(
    [string]$ComposeFile = "docker-compose.postgres-ha-lab.yml",
    [switch]$AllowStartAfterPromotion
)

$ErrorActionPreference = "Stop"

function Invoke-LabCompose {
    param([string[]]$ComposeArgs)
    & docker compose -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose lab command failed: $($ComposeArgs -join ' ')"
    }
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

Write-Host "CampusEnroll PostgreSQL HA Lab - startup" -ForegroundColor Yellow
Write-Host "Compose file: $ComposeFile"
Write-Host "This starts isolated lab containers only: postgres-primary-lab and postgres-replica-lab."
Write-Host "It does not run down -v and does not touch campusenroll-postgres or campusenroll_pg_data."

$replicaRunning = docker inspect --format "{{.State.Status}}" postgres-replica-lab 2>$null
if ($LASTEXITCODE -eq 0 -and $replicaRunning -eq "running" -and -not $AllowStartAfterPromotion) {
    $labUser = if ($env:POSTGRES_LAB_USER) { $env:POSTGRES_LAB_USER } else { "campus_lab" }
    $labDatabase = if ($env:POSTGRES_LAB_DB) { $env:POSTGRES_LAB_DB } else { "campusenroll_lab" }
    $replicaRecovery = (docker exec postgres-replica-lab psql -U $labUser -d $labDatabase -tAc "SELECT pg_is_in_recovery();" 2>$null).Trim()
    if ($replicaRecovery -eq "f") {
        throw "postgres-replica-lab appears promoted (pg_is_in_recovery() = false). Refusing to restart the old lab primary because that can create split brain. Rebuild the lab topology intentionally before running up again, or pass -AllowStartAfterPromotion only if you know exactly why."
    }
}

$env:COMPOSE_IGNORE_ORPHANS = "true"
Invoke-LabCompose -ComposeArgs @("config", "--quiet")
Invoke-LabCompose -ComposeArgs @("up", "-d", "postgres-primary-lab", "postgres-replica-lab")

Write-Host ""
Write-Host "Lab startup requested. Run database/scripts/postgres-ha-lab-status.ps1 to inspect health." -ForegroundColor Green
