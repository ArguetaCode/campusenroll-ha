param(
    [string]$AdvertiseAddress,
    [string]$ListenAddress = "0.0.0.0:2377"
)

$ErrorActionPreference = "Stop"

$state = docker info --format "{{.Swarm.LocalNodeState}}" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Docker does not appear available on this machine."
}

if (-not $AdvertiseAddress) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Sort-Object InterfaceMetric, SkipAsSource |
        Select-Object -First 1 -ExpandProperty IPAddress)
    if (-not $ip) {
        throw "Could not infer a LAN IPv4 address. Re-run with -AdvertiseAddress <LAN_IP>."
    }
    $AdvertiseAddress = $ip
}

if ($state -eq "active") {
    Write-Host "Swarm already active on this node." -ForegroundColor Yellow
} else {
    docker swarm init --advertise-addr $AdvertiseAddress --listen-addr $ListenAddress
    if ($LASTEXITCODE -ne 0) {
        throw "docker swarm init failed."
    }
}

Write-Host ""
Write-Host "Manager join token:" -ForegroundColor Cyan
docker swarm join-token manager
Write-Host ""
Write-Host "Worker join token:" -ForegroundColor Cyan
docker swarm join-token worker

