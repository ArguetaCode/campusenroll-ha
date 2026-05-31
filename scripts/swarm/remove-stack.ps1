param(
    [string]$StackName = "campusenroll"
)

$ErrorActionPreference = "Stop"

docker stack rm $StackName
if ($LASTEXITCODE -ne 0) {
    throw "docker stack rm failed."
}

Write-Host "Requested stack removal for $StackName." -ForegroundColor Green

