param(
  [string[]]$DbNodes = @("192.168.0.12", "192.168.0.10", "192.168.0.11"),
  [string]$HaProxyHost = "192.168.0.13"
)

$ErrorActionPreference = "Continue"

function Test-TcpPort {
  param([string]$HostName, [int]$Port)
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect($HostName, $Port, $null, $null)
    $ok = $async.AsyncWaitHandle.WaitOne(3000)
    if ($ok) { $client.EndConnect($async) }
    [pscustomobject]@{ Host = $HostName; Port = $Port; Open = [bool]$ok }
  } catch {
    [pscustomobject]@{ Host = $HostName; Port = $Port; Open = $false; Error = $_.Exception.Message }
  } finally {
    $client.Close()
  }
}

Write-Host "Ping checks"
foreach ($hostName in ($DbNodes + $HaProxyHost)) {
  [pscustomobject]@{ Host = $hostName; Ping = Test-Connection -ComputerName $hostName -Count 1 -Quiet }
}

Write-Host ""
Write-Host "DB node ports"
foreach ($node in $DbNodes) {
  foreach ($port in @(2379, 2380, 5432, 8008)) {
    Test-TcpPort -HostName $node -Port $port
  }
}

Write-Host ""
Write-Host "HAProxy ports"
foreach ($port in @(5000, 7000)) {
  Test-TcpPort -HostName $HaProxyHost -Port $port
}

Write-Host ""
Write-Host "Patroni REST API"
foreach ($node in $DbNodes) {
  try {
    Invoke-RestMethod -Uri "http://${node}:8008/patroni" -TimeoutSec 5 |
      Select-Object @{Name="Node";Expression={$node}}, name, role, state
  } catch {
    [pscustomobject]@{ Node = $node; Error = $_.Exception.Message }
  }
}
