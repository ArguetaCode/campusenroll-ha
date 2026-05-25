param(
    [string]$ComposeFile = "docker-compose.postgres-ha-lab.yml"
)

$ErrorActionPreference = "Stop"

Write-Host "CampusEnroll PostgreSQL HA Lab - status" -ForegroundColor Yellow
foreach ($container in @("postgres-primary-lab", "postgres-replica-lab")) {
    $status = docker inspect --format "{{.Name}} -> status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}" $container 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $status"
    } else {
        Write-Host "  $container -> not found" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Published ports:"
docker ps --filter "name=postgres-primary-lab" --filter "name=postgres-replica-lab" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
