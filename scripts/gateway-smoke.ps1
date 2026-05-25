param(
    [switch]$SkipCleanup,
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    if (-not $ComposeArgs -or $ComposeArgs.Count -eq 0) {
        throw "Invoke-Compose received no arguments."
    }
    & docker compose -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($ComposeArgs -join ' ')"
    }
}

function Test-Endpoint200 {
    param([string]$Url)
    $attempts = 8
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 20
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK]  $Url -> 200" -ForegroundColor Green
                return
            }
        } catch {
            if ($i -eq $attempts) {
                Write-Host "[ERR] $Url -> $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            Start-Sleep -Seconds 3
        }
    }
    throw "Endpoint failed after retries: $Url"
}

function Wait-ContainerHealthy {
    param([string]$ContainerName, [int]$MaxAttempts = 30)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $status = (& docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}" $ContainerName 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "Container not found: $ContainerName"
        }
        if ($status -eq "healthy" -or $status -eq "no-healthcheck") {
            Write-Host "[OK]  $ContainerName -> $status" -ForegroundColor Green
            return
        }
        if ($i -eq $MaxAttempts) {
            throw "$ContainerName did not become healthy in time. Last status: $status"
        }
        Start-Sleep -Seconds 3
    }
}

Write-Host "CampusEnroll-HA Gateway Smoke Test" -ForegroundColor Yellow
Write-Host "Compose file: $ComposeFile"
Write-Host "Gateway URL:  $GatewayBaseUrl"

if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

if (-not $SkipCleanup) {
    Write-Step "Cleanup previous stack (down -v)"
    Invoke-Compose -ComposeArgs @("down", "-v")
} else {
    Write-Step "Skipping cleanup because -SkipCleanup was provided"
}

Write-Step "Start infrastructure (PostgreSQL, Redis, RabbitMQ)"
Invoke-Compose -ComposeArgs @("up", "-d", "campusenroll-postgres", "campusenroll-redis", "campusenroll-rabbitmq")

Write-Step "Run Flyway migrations"
Invoke-Compose -ComposeArgs @("--profile", "db-migration", "run", "--rm", "campusenroll-flyway")

Write-Step "Start full stack (services + gateway + observability)"
Invoke-Compose -ComposeArgs @("up", "-d")

Write-Step "Wait for gateway container to report healthy"
Wait-ContainerHealthy -ContainerName "campusenroll-student-service"
Wait-ContainerHealthy -ContainerName "campusenroll-course-service"
Wait-ContainerHealthy -ContainerName "campusenroll-billing-service"
Wait-ContainerHealthy -ContainerName "campusenroll-notification-service"
Wait-ContainerHealthy -ContainerName "campusenroll-enrollment-service"
Wait-ContainerHealthy -ContainerName "campusenroll-api-gateway"

Write-Step "Validate gateway endpoints"
$urls = @(
    "$GatewayBaseUrl/health",
    "$GatewayBaseUrl/students",
    "$GatewayBaseUrl/api/students",
    "$GatewayBaseUrl/courses",
    "$GatewayBaseUrl/sections",
    "$GatewayBaseUrl/payments",
    "$GatewayBaseUrl/notifications",
    "$GatewayBaseUrl/api/enrollments",
    "$GatewayBaseUrl/api/students/1/enrollments"
)

foreach ($url in $urls) {
    Test-Endpoint200 -Url $url
}

Write-Host ""
Write-Host "Gateway smoke test completed successfully." -ForegroundColor Green
