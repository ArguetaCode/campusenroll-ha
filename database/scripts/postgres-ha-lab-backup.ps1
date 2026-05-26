param(
    [string]$OutputDir = "./database/postgres-ha-lab/backups",
    [string]$Database = $env:POSTGRES_LAB_DB,
    [string]$User = $env:POSTGRES_LAB_USER
)

$ErrorActionPreference = "Stop"

if (-not $Database) { $Database = "campusenroll_lab" }
if (-not $User) { $User = "campus_lab" }

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDir ("{0}_{1}.dump" -f $Database, $timestamp)

Write-Host "CampusEnroll PostgreSQL HA Lab - backup" -ForegroundColor Yellow
Write-Host "LAB ONLY / NOT FOR PRODUCTION."
Write-Host "Source container: postgres-primary-lab"
Write-Host "Database:         $Database"
Write-Host "User:             $User"
Write-Host "Output file:      $outputFile"

$containerDump = "/tmp/${Database}_${timestamp}.dump"
docker exec postgres-primary-lab pg_dump -U $User -d $Database -Fc -f $containerDump
if ($LASTEXITCODE -ne 0) {
    throw "Lab backup failed."
}

docker cp "postgres-primary-lab:${containerDump}" $outputFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy lab backup from container."
}

docker exec postgres-primary-lab rm -f $containerDump | Out-Null

Write-Host "Lab backup generated: $outputFile" -ForegroundColor Green
