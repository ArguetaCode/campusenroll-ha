param(
  [string[]]$Nodes = @("192.168.0.12", "192.168.0.10", "192.168.0.11"),
  [int]$PatroniPort = 8008,
  [string]$Database = "campusenroll",
  [string]$DbUser = "campus",
  [string]$DbPassword = "campus123",
  [string]$HaProxyHost = "192.168.0.13",
  [int]$HaProxyPostgresPort = 5000,
  [int]$HaProxyStatsPort = 7000
)

$ErrorActionPreference = "Stop"

function Invoke-JsonGet {
  param([string]$Uri)
  try {
    Invoke-RestMethod -Method Get -Uri $Uri -TimeoutSec 5
  } catch {
    [pscustomobject]@{ error = $_.Exception.Message }
  }
}

Write-Host "Patroni cluster status"
foreach ($node in $Nodes) {
  $status = Invoke-JsonGet "http://${node}:${PatroniPort}/patroni"
  $primary = Invoke-JsonGet "http://${node}:${PatroniPort}/primary"
  [pscustomobject]@{
    Node = $node
    Name = $status.name
    Role = $status.role
    State = $status.state
    Timeline = $status.xlog.timeline
    PrimaryEndpoint = if ($primary.error) { "not primary" } else { "primary" }
    Error = $status.error
  }
}

Write-Host ""
Write-Host "HAProxy write endpoint check"
$env:PGPASSWORD = $DbPassword
psql -h $HaProxyHost -p $HaProxyPostgresPort -U $DbUser -d $Database -c "SELECT inet_server_addr() AS server_addr, pg_is_in_recovery() AS in_recovery;"

Write-Host ""
Write-Host "HAProxy stats endpoint"
Invoke-WebRequest -UseBasicParsing -Uri "http://${HaProxyHost}:${HaProxyStatsPort}/" -TimeoutSec 5 | Select-Object StatusCode, StatusDescription
