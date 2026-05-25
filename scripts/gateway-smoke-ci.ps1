param(
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://localhost:8080",
    [int]$ContainerWaitAttempts = 30,
    [int]$EndpointRetryAttempts = 8,
    [switch]$SkipFlyway
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

function Wait-ContainerHealthy {
    param(
        [string]$ContainerName,
        [int]$MaxAttempts = 30
    )

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

function Test-Endpoint200 {
    param(
        [string]$Url,
        [int]$Attempts = 8
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 20
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK]  $Url -> 200" -ForegroundColor Green
                return
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host "[ERR] $Url -> $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            Start-Sleep -Seconds 3
        }
    }

    throw "Endpoint failed after retries: $Url"
}

Write-Host "CampusEnroll-HA Gateway Smoke Test (CI Mode)" -ForegroundColor Yellow
Write-Host "Compose file: $ComposeFile"
Write-Host "Gateway URL:  $GatewayBaseUrl"

if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

Write-Step "Start infrastructure (non-destructive)"
Invoke-Compose -ComposeArgs @("up", "-d", "campusenroll-postgres", "campusenroll-redis", "campusenroll-rabbitmq")

if (-not $SkipFlyway) {
    Write-Step "Run Flyway migrations (idempotent)"
    Invoke-Compose -ComposeArgs @("--profile", "db-migration", "run", "--rm", "campusenroll-flyway")
} else {
    Write-Step "Skipping Flyway because -SkipFlyway was provided"
}

Write-Step "Start full stack (non-destructive)"
Invoke-Compose -ComposeArgs @("up", "-d")

Write-Step "Wait for critical containers to be healthy"
Wait-ContainerHealthy -ContainerName "campusenroll-student-service" -MaxAttempts $ContainerWaitAttempts
Wait-ContainerHealthy -ContainerName "campusenroll-course-service" -MaxAttempts $ContainerWaitAttempts
Wait-ContainerHealthy -ContainerName "campusenroll-billing-service" -MaxAttempts $ContainerWaitAttempts
Wait-ContainerHealthy -ContainerName "campusenroll-notification-service" -MaxAttempts $ContainerWaitAttempts
Wait-ContainerHealthy -ContainerName "campusenroll-enrollment-service" -MaxAttempts $ContainerWaitAttempts
Wait-ContainerHealthy -ContainerName "campusenroll-api-gateway" -MaxAttempts $ContainerWaitAttempts

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
    Test-Endpoint200 -Url $url -Attempts $EndpointRetryAttempts
}

Write-Host ""
Write-Host "Gateway smoke CI test completed successfully." -ForegroundColor Green
