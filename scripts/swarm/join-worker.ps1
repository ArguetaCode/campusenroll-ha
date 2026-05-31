param(
    [Parameter(Mandatory = $true)]
    [string]$WorkerToken,
    [Parameter(Mandatory = $true)]
    [string]$ManagerAddress,
    [string]$AdvertiseAddress
)

$ErrorActionPreference = "Stop"

$state = docker info --format "{{.Swarm.LocalNodeState}}" 2>$null
if ($state -eq "active") {
    throw "This node already belongs to a swarm. Leave it first if you intend to re-join."
}

$args = @("swarm", "join", "--token", $WorkerToken)
if ($AdvertiseAddress) {
    $args += @("--advertise-addr", $AdvertiseAddress)
}
$args += $ManagerAddress

docker @args
if ($LASTEXITCODE -ne 0) {
    throw "docker swarm join (worker) failed."
}

