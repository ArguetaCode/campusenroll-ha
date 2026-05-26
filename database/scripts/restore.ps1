param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [switch]$ConfirmRestore
)

$env:POSTGRES_DB = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "campusenroll" }
$env:POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "campus" }
$env:POSTGRES_PASSWORD = if ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "" }
$hostName = if ($env:POSTGRES_HOST) { $env:POSTGRES_HOST } else { "127.0.0.1" }
$port = if ($env:POSTGRES_PORT) { $env:POSTGRES_PORT } else { "55432" }

if (-not (Test-Path $BackupFile)) {
    throw "backup file not found: $BackupFile"
}

if (-not $ConfirmRestore) {
    throw "NOT FOR PRODUCTION: restore is destructive for the target database because pg_restore runs with --clean --if-exists. Re-run with -ConfirmRestore only against an isolated restore target or an explicitly approved non-production database."
}

$containerExists = docker ps --format '{{.Names}}' | Select-String -Pattern '^campusenroll-postgres$'

Write-Host "CampusEnroll database restore - NOT FOR PRODUCTION" -ForegroundColor Yellow
Write-Warning "This restore will run pg_restore --clean --if-exists and can drop/recreate objects in the target database."
Write-Host "Backup file: $BackupFile"
Write-Host "Target database: ${env:POSTGRES_DB}"
Write-Host "Target user:     ${env:POSTGRES_USER}"

if ($containerExists) {
    Write-Host "Target mode:     docker exec -> campusenroll-postgres"
    Get-Content -Path $BackupFile -AsByteStream | docker exec -i -e PGPASSWORD=$env:POSTGRES_PASSWORD campusenroll-postgres pg_restore -U $env:POSTGRES_USER -d $env:POSTGRES_DB --clean --if-exists --no-owner --no-privileges
} else {
    Write-Host "Target mode:     network -> ${hostName}:${port}/${env:POSTGRES_DB}"
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    pg_restore -h $hostName -p $port -U $env:POSTGRES_USER -d $env:POSTGRES_DB --clean --if-exists --no-owner --no-privileges $BackupFile
}

Write-Host "restore completed from: $BackupFile"
