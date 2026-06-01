param(
  [string[]]$Nodes = @("192.168.0.12", "192.168.0.10", "192.168.0.11"),
  [string]$HaProxyHost = "192.168.0.13",
  [int]$HaProxyPostgresPort = 5000,
  [string]$Database = "campusenroll",
  [string]$DbUser = "campus",
  [string]$DbPassword = "campus123",
  [int]$WatchSeconds = 90
)

$ErrorActionPreference = "Continue"
$env:PGPASSWORD = $DbPassword

Write-Host "Current Patroni roles"
foreach ($node in $Nodes) {
  try {
    Invoke-RestMethod -Uri "http://${node}:8008/patroni" -TimeoutSec 5 |
      Select-Object @{Name="Node";Expression={$node}}, name, role, state
  } catch {
    [pscustomobject]@{ Node = $node; Error = $_.Exception.Message }
  }
}

Write-Host ""
Write-Host "Stop the current primary on its DB PC now, for example:"
Write-Host "docker compose --profile jared -f docker-compose.patroni.yml stop patroni-jared"
Write-Host "Then this script will watch HAProxy until a writable primary is available again."
Write-Host ""

$deadline = (Get-Date).AddSeconds($WatchSeconds)
do {
  try {
    $result = psql -h $HaProxyHost -p $HaProxyPostgresPort -U $DbUser -d $Database -tAc "SELECT pg_is_in_recovery();" 2>$null
    $ok = ($LASTEXITCODE -eq 0 -and $result.Trim() -eq "f")
    [pscustomobject]@{ Time = (Get-Date).ToString("HH:mm:ss"); HaProxyWritable = $ok; PgIsInRecovery = $result.Trim() }
    if ($ok) { exit 0 }
  } catch {
    [pscustomobject]@{ Time = (Get-Date).ToString("HH:mm:ss"); HaProxyWritable = $false; Error = $_.Exception.Message }
  }
  Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)

Write-Error "HAProxy did not expose a writable primary within ${WatchSeconds}s."
exit 1
