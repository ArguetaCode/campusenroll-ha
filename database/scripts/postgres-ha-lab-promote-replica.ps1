param(
    [string]$Database = $env:POSTGRES_LAB_DB,
    [string]$User = $env:POSTGRES_LAB_USER,
    [switch]$ConfirmPromoteLab
)

$ErrorActionPreference = "Stop"

if (-not $Database) { $Database = "campusenroll_lab" }
if (-not $User) { $User = "campus_lab" }

if (-not $ConfirmPromoteLab) {
    throw "Replica promotion changes the lab topology and stops postgres-primary-lab. Re-run with -ConfirmPromoteLab only for isolated lab testing."
}

Write-Host "CampusEnroll PostgreSQL HA Lab - promote replica" -ForegroundColor Yellow
Write-Warning "This is destructive to the lab replication topology only. It does not delete volumes and does not touch campusenroll-postgres."

$primaryState = docker inspect --format "{{.State.Status}}" postgres-primary-lab 2>$null
if ($LASTEXITCODE -eq 0 -and $primaryState -eq "running") {
    docker stop postgres-primary-lab | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stop postgres-primary-lab."
    }
} else {
    Write-Host "postgres-primary-lab is not running; continuing with replica promotion."
}

docker exec postgres-replica-lab psql -U $User -d $Database -v ON_ERROR_STOP=1 -c "SELECT pg_promote(true, 60);"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to promote postgres-replica-lab."
}

for ($i = 1; $i -le 20; $i++) {
    $recovery = (docker exec postgres-replica-lab psql -U $User -d $Database -tAc "SELECT pg_is_in_recovery();" 2>$null).Trim()
    if ($recovery -eq "f") {
        break
    }
    Start-Sleep -Seconds 1
}

if ($recovery -ne "f") {
    throw "Replica did not leave recovery mode after promotion."
}

$probeId = [Guid]::NewGuid().ToString()
docker exec postgres-replica-lab psql -U $User -d $Database -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS ha_lab; CREATE TABLE IF NOT EXISTS ha_lab.promotion_probe (id text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now()); INSERT INTO ha_lab.promotion_probe(id) VALUES ('$probeId');" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Promoted replica did not accept writes."
}

Write-Host "postgres-replica-lab promoted and accepted write probe: $probeId" -ForegroundColor Green
Write-Host "To get a replica again, rebuild the lab replica from the new primary or recreate the lab topology intentionally."
