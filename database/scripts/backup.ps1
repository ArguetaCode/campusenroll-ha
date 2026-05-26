param(
    [string]$OutputDir = "./database/backups"
)

$env:POSTGRES_DB = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "campusenroll" }
$env:POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "campus" }
$env:POSTGRES_PASSWORD = if ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "" }
$schema = if ($env:POSTGRES_SCHEMA) { $env:POSTGRES_SCHEMA } else { "campusenroll" }
$hostName = if ($env:POSTGRES_HOST) { $env:POSTGRES_HOST } else { "127.0.0.1" }
$port = if ($env:POSTGRES_PORT) { $env:POSTGRES_PORT } else { "55432" }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$outputFile = Join-Path $OutputDir ("{0}_{1}_{2}.dump" -f $env:POSTGRES_DB, $schema, $timestamp)

$containerExists = docker ps --format '{{.Names}}' | Select-String -Pattern '^campusenroll-postgres$'

Write-Host "CampusEnroll database backup" -ForegroundColor Yellow
Write-Host "This is a logical backup helper, not a production backup system."
Write-Host "Database: ${env:POSTGRES_DB}"
Write-Host "Schema:   $schema"
Write-Host "Output:   $outputFile"

if ($containerExists) {
    Write-Host "[info] using docker exec against campusenroll-postgres"
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    docker exec -e PGPASSWORD=$env:POSTGRES_PASSWORD campusenroll-postgres pg_dump -U $env:POSTGRES_USER -d $env:POSTGRES_DB -n $schema -Fc > $outputFile
} else {
    Write-Host "[info] using network connection to ${hostName}:${port}"
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    pg_dump -h $hostName -p $port -U $env:POSTGRES_USER -d $env:POSTGRES_DB -n $schema -Fc -f $outputFile
}

Write-Host "backup generated: $outputFile"
