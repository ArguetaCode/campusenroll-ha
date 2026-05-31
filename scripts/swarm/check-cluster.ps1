param(
    [string]$StackName = "campusenroll"
)

$ErrorActionPreference = "Stop"

Write-Host "Nodes" -ForegroundColor Cyan
docker node ls
Write-Host ""

Write-Host "Services" -ForegroundColor Cyan
docker service ls
Write-Host ""

Write-Host "Stack services" -ForegroundColor Cyan
docker stack services $StackName
Write-Host ""

Write-Host "Stack tasks" -ForegroundColor Cyan
docker stack ps $StackName --no-trunc

