param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [string]$Database = $env:POSTGRES_LAB_DB,
    [string]$User = $env:POSTGRES_LAB_USER,
    [string]$Password = $env:POSTGRES_LAB_PASSWORD,
    [switch]$ConfirmRestoreDrill
)

$ErrorActionPreference = "Stop"

if (-not $Database) { $Database = "campusenroll_lab" }
if (-not $User) { $User = "campus_lab" }
if (-not $Password) { $Password = "campus_lab123" }

if (-not (Test-Path -LiteralPath $BackupFile)) {
    throw "Backup file not found: $BackupFile"
}

if (-not $ConfirmRestoreDrill) {
    throw "Restore drill creates an ephemeral lab container and restores the dump there. Re-run with -ConfirmRestoreDrill to proceed."
}

$restoreContainer = "postgres-restore-drill-lab"
$existing = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $restoreContainer }
if ($existing) {
    throw "Container $restoreContainer already exists. Remove it manually only if it is from a previous restore drill."
}

Write-Host "CampusEnroll PostgreSQL HA Lab - restore drill" -ForegroundColor Yellow
Write-Host "This uses an ephemeral container with no named volume and does not touch primary/replica lab data."

docker run -d --rm `
    --name $restoreContainer `
    --network campusenroll_postgres_ha_lab_net `
    -e POSTGRES_DB=$Database `
    -e POSTGRES_USER=$User `
    -e POSTGRES_PASSWORD=$Password `
    postgres:16 | Out-Null

try {
    $ready = $false
    for ($i = 1; $i -le 60; $i++) {
        $state = docker inspect --format "{{.State.Status}}" $restoreContainer 2>$null
        if ($LASTEXITCODE -ne 0 -or $state -ne "running") {
            throw "Restore drill PostgreSQL container stopped unexpectedly. State: $state"
        }

        docker exec $restoreContainer pg_isready -U $User -d $Database | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $readyCheck = docker exec $restoreContainer psql -U $User -d $Database -tAc "SELECT 1;" 2>$null
            if ($LASTEXITCODE -eq 0 -and $readyCheck.Trim() -eq "1") {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }

    if (-not $ready) {
        throw "Restore drill PostgreSQL container did not become ready."
    }

    docker cp $BackupFile "${restoreContainer}:/tmp/restore.dump"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy backup into restore drill container."
    }

    docker exec $restoreContainer pg_restore -U $User -d $Database --clean --if-exists --no-owner --no-privileges /tmp/restore.dump
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed in restore drill container."
    }

    docker exec $restoreContainer psql -U $User -d $Database -c "\dt ha_lab.*"
    if ($LASTEXITCODE -ne 0) {
        throw "Restore drill validation query failed."
    }

    Write-Host "Restore drill completed successfully in ephemeral container." -ForegroundColor Green
} finally {
    docker stop $restoreContainer 2>$null | Out-Null
}
