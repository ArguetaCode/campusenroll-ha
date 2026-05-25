param(
    [string]$Database = $env:POSTGRES_LAB_DB,
    [string]$User = $env:POSTGRES_LAB_USER,
    [switch]$SkipBasicReplicationTest
)

$ErrorActionPreference = "Stop"

if (-not $Database) { $Database = "campusenroll_lab" }
if (-not $User) { $User = "campus_lab" }

function Invoke-Psql {
    param(
        [string]$Container,
        [string]$Sql,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $script:LastPsqlExitCode = 0
        $ErrorActionPreference = "Continue"
        $output = docker exec $Container psql -U $User -d $Database -tAc $Sql 2>&1
        $script:LastPsqlExitCode = $LASTEXITCODE
        if ($script:LastPsqlExitCode -ne 0 -and -not $AllowFailure) {
            throw "psql failed in ${Container}: $output"
        }
        return $output
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

Write-Host "CampusEnroll PostgreSQL HA Lab - replication check" -ForegroundColor Yellow
Write-Host "Database: $Database"
Write-Host "User:     $User"

$primaryRecovery = (Invoke-Psql -Container "postgres-primary-lab" -Sql "SELECT pg_is_in_recovery();").Trim()
$replicaRecovery = (Invoke-Psql -Container "postgres-replica-lab" -Sql "SELECT pg_is_in_recovery();").Trim()

Write-Host "Primary pg_is_in_recovery(): $primaryRecovery"
Write-Host "Replica pg_is_in_recovery(): $replicaRecovery"

if ($primaryRecovery -ne "f") {
    throw "Expected primary to return false for pg_is_in_recovery()."
}

if ($replicaRecovery -ne "t") {
    throw "Expected replica to return true for pg_is_in_recovery()."
}

Write-Host ""
Write-Host "Primary pg_stat_replication:"
Invoke-Psql -Container "postgres-primary-lab" -Sql "SELECT application_name || '|' || state || '|' || sync_state || '|' || COALESCE(write_lag::text,'') || '|' || COALESCE(flush_lag::text,'') || '|' || COALESCE(replay_lag::text,'') FROM pg_stat_replication;"

if (-not $SkipBasicReplicationTest) {
    Write-Host ""
    Write-Host "Running small lab-only replication test. This creates rows in ha_lab.replication_probe." -ForegroundColor Yellow
    $probeId = [Guid]::NewGuid().ToString()
    $createSql = "CREATE SCHEMA IF NOT EXISTS ha_lab; CREATE TABLE IF NOT EXISTS ha_lab.replication_probe (id text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now()); INSERT INTO ha_lab.replication_probe(id) VALUES ('$probeId');"
    Invoke-Psql -Container "postgres-primary-lab" -Sql $createSql | Out-Null

    $found = ""
    for ($i = 1; $i -le 20; $i++) {
        $found = (Invoke-Psql -Container "postgres-replica-lab" -Sql "SELECT id FROM ha_lab.replication_probe WHERE id = '$probeId';").Trim()
        if ($found -eq $probeId) {
            break
        }
        Start-Sleep -Seconds 1
    }

    if ($found -ne $probeId) {
        throw "Probe row did not appear on replica within timeout."
    }

    Write-Host "Probe row replicated: $probeId" -ForegroundColor Green

    Invoke-Psql -Container "postgres-replica-lab" -Sql "INSERT INTO ha_lab.replication_probe(id) VALUES ('replica-write-should-fail');" -AllowFailure | Out-Null
    if ($script:LastPsqlExitCode -eq 0) {
        throw "Replica unexpectedly accepted a write."
    }
    Write-Host "Replica write rejected as expected." -ForegroundColor Green
}

Write-Host ""
Write-Host "Replication check completed." -ForegroundColor Green
