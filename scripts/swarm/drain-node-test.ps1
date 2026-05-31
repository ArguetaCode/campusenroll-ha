param(
    [Parameter(Mandatory = $true)]
    [string]$NodeName,
    [string]$StackName = "campusenroll",
    [int]$WaitSeconds = 20,
    [switch]$ReactivateNode
)

$ErrorActionPreference = "Stop"

Write-Host "Draining node $NodeName ..." -ForegroundColor Yellow
docker node update --availability drain $NodeName
if ($LASTEXITCODE -ne 0) {
    throw "Failed to drain node $NodeName."
}

Write-Host "Waiting $WaitSeconds seconds for task re-scheduling ..." -ForegroundColor Yellow
Start-Sleep -Seconds $WaitSeconds

Write-Host "Cluster summary after drain" -ForegroundColor Cyan
docker node ls
docker stack services $StackName
docker stack ps $StackName

if ($ReactivateNode) {
    Write-Host "Reactivating node $NodeName ..." -ForegroundColor Yellow
    docker node update --availability active $NodeName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to reactivate node $NodeName."
    }
    Start-Sleep -Seconds 5
    docker node ls
}

