param(
    [switch]$SkipCleanup,
    [switch]$AllowDestructiveCleanup,
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://localhost:8080",
    [int]$EndpointRetryAttempts = 8,
    [int]$EndpointTimeoutSeconds = 10
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

function Get-WebFailureMessage {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Label
    )

    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.StatusCode) {
        return "[ERROR] $Label returned HTTP $([int]$response.StatusCode)"
    }

    if ($ErrorRecord.Exception.Message -match "timed out|timeout|operation has timed out") {
        return "[ERROR] $Label timeout"
    }

    if ($ErrorRecord.Exception.Message -match "returned HTTP|returned invalid JSON|returned unexpected payload") {
        return "[ERROR] $($ErrorRecord.Exception.Message)"
    }

    return "[ERROR] $Label connection failed: $($ErrorRecord.Exception.Message)"
}

function Test-Endpoint200 {
    param(
        [string]$Url,
        [string]$Label = $Url,
        [int]$Attempts = 8,
        [int]$TimeoutSeconds = 10
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec $TimeoutSeconds
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK]  $Label -> 200" -ForegroundColor Green
                return
            }

            if ($i -eq $Attempts) {
                Write-Host "[ERROR] $Label returned HTTP $($response.StatusCode)" -ForegroundColor Red
                throw "$Label returned HTTP $($response.StatusCode)"
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label $Label) -ForegroundColor Red
                throw "$Label failed after $Attempts attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
    throw "$Label failed after retries: $Url"
}

function Test-HealthEndpoint {
    param(
        [string]$Url,
        [string]$Label,
        [int]$Attempts = 8,
        [int]$TimeoutSeconds = 10
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec $TimeoutSeconds
            if ($response.StatusCode -ne 200) {
                if ($i -eq $Attempts) {
                    Write-Host "[ERROR] $Label health returned HTTP $($response.StatusCode)" -ForegroundColor Red
                    throw "$Label health returned HTTP $($response.StatusCode)"
                }
                Start-Sleep -Seconds 2
                continue
            }

            try {
                $payload = $response.Content | ConvertFrom-Json
            } catch {
                Write-Host "[ERROR] $Label health returned invalid JSON" -ForegroundColor Red
                throw "$Label health returned invalid JSON"
            }

            if ($payload.status -ne "UP") {
                Write-Host "[ERROR] $Label health returned unexpected payload: $($response.Content)" -ForegroundColor Red
                throw "$Label health returned unexpected payload"
            }

            Write-Host "[OK]  $Label health -> UP" -ForegroundColor Green
            return
        } catch {
            if ($i -eq $Attempts) {
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label "$Label health endpoint") -ForegroundColor Red
                throw "$Label health failed after $Attempts attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Test-ReadinessGate {
    param(
        [string]$ServiceName,
        [string[]]$DockerArgs,
        [string]$ExpectedOutput = "",
        [int]$MaxAttempts = 15,
        [int]$SleepSeconds = 2
    )

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $output = & docker @DockerArgs 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($output | ForEach-Object { "$_" }) -join "`n"

        $outputMatches = $true
        if ($ExpectedOutput -ne "") {
            $outputMatches = $outputText -match $ExpectedOutput
        }

        if ($exitCode -eq 0 -and $outputMatches) {
            Write-Host "[OK]  $ServiceName readiness check passed" -ForegroundColor Green
            return
        }

        Write-Host "[WARNING] $ServiceName readiness check attempt $i/$MaxAttempts failed: $outputText" -ForegroundColor Yellow

        if ($i -eq $MaxAttempts) {
            Write-Host "[ERROR] $ServiceName readiness check failed" -ForegroundColor Red
            throw "$ServiceName readiness check failed"
        }

        Start-Sleep -Seconds $SleepSeconds
    }
}

function Test-InfrastructureReadiness {
    Write-Step "Validate infrastructure readiness gates"

    Test-ReadinessGate `
        -ServiceName "PostgreSQL" `
        -DockerArgs @("exec", "campusenroll-postgres", "pg_isready", "-U", "campus")

    Test-ReadinessGate `
        -ServiceName "Redis" `
        -DockerArgs @("exec", "campusenroll-redis", "redis-cli", "ping") `
        -ExpectedOutput "PONG"

    Test-ReadinessGate `
        -ServiceName "RabbitMQ" `
        -DockerArgs @("exec", "campusenroll-rabbitmq", "rabbitmq-diagnostics", "ping")
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

if ($AllowDestructiveCleanup) {
    throw "Destructive cleanup is disabled in gateway-smoke.ps1. This smoke test never deletes Docker volumes."
} else {
    if ($SkipCleanup) {
        Write-Step "Safe mode: -SkipCleanup accepted for backwards compatibility."
    } else {
        Write-Step "Safe mode: skipping cleanup. This smoke test does not delete Docker volumes."
    }
}

Write-Step "Start infrastructure (PostgreSQL, Redis, RabbitMQ)"
Invoke-Compose -ComposeArgs @("up", "-d", "campusenroll-postgres", "campusenroll-redis", "campusenroll-rabbitmq")
Test-InfrastructureReadiness

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

Write-Step "Validate gateway health endpoints"
$healthEndpoints = @(
    @{ Label = "gateway /health"; Url = "$GatewayBaseUrl/health" },
    @{ Label = "student-service"; Url = "$GatewayBaseUrl/health/student-service" },
    @{ Label = "course-service"; Url = "$GatewayBaseUrl/health/course-service" },
    @{ Label = "billing-service"; Url = "$GatewayBaseUrl/health/billing-service" },
    @{ Label = "notification-service"; Url = "$GatewayBaseUrl/health/notification-service" },
    @{ Label = "enrollment-service"; Url = "$GatewayBaseUrl/health/enrollment-service" }
)

foreach ($endpoint in $healthEndpoints) {
    Test-HealthEndpoint -Url $endpoint.Url -Label $endpoint.Label -Attempts $EndpointRetryAttempts -TimeoutSeconds $EndpointTimeoutSeconds
}

Write-Step "Validate gateway read endpoints"
$urls = @(
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
    Test-Endpoint200 -Url $url -Attempts $EndpointRetryAttempts -TimeoutSeconds $EndpointTimeoutSeconds
}

Write-Host ""
Write-Host "Gateway smoke test completed successfully." -ForegroundColor Green
