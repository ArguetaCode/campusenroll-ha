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

function Write-ComposeDiagnostics {
    Write-Host ""
    Write-Host "Diagnostics timestamp: $(Get-Date -Format o)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Docker Compose status:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile ps

    Write-Host ""
    Write-Host "RabbitMQ queues:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile exec -T campusenroll-rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers

    Write-Host ""
    Write-Host "RabbitMQ payment exchanges:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile exec -T campusenroll-rabbitmq rabbitmqctl list_exchanges name type durable | Select-String -Pattern "campusenroll|^name"

    Write-Host ""
    Write-Host "RabbitMQ payment bindings:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile exec -T campusenroll-rabbitmq rabbitmqctl list_bindings source_name destination_name routing_key | Select-String -Pattern "campusenroll|payment|^source"

    Write-Host ""
    Write-Host "Redis memory/stats:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile exec -T campusenroll-redis redis-cli INFO memory
    & docker compose -f $ComposeFile exec -T campusenroll-redis redis-cli INFO stats

    Write-Host ""
    Write-Host "PostgreSQL connection summary:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile exec -T campusenroll-postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select datname, state, count(*) from pg_stat_activity group by datname, state order by datname, state;"'

    $diagnosticServices = @(
        "campusenroll-api-gateway",
        "billing-service",
        "notification-service",
        "enrollment-service",
        "campusenroll-rabbitmq",
        "campusenroll-redis"
    )

    foreach ($service in $diagnosticServices) {
        Write-Host ""
        Write-Host "Last logs for ${service}:" -ForegroundColor Yellow
        & docker compose -f $ComposeFile logs --tail 80 $service
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
            Write-ComposeDiagnostics
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
                Write-ComposeDiagnostics
                throw
            }
            Start-Sleep -Seconds 3
        }
    }

    throw "Endpoint failed after retries: $Url"
}

function Test-PaymentWriteReadiness {
    param(
        [string]$BaseUrl,
        [int]$Attempts = 8
    )

    $url = "$BaseUrl/payments"
    $studentId = Get-Random -Minimum 100000 -Maximum 999999
    $enrollmentId = Get-Random -Minimum 1000000 -Maximum 9999999
    for ($i = 1; $i -le $Attempts; $i++) {
        $payload = @{
            enrollmentId = $enrollmentId
            studentId = $studentId
            amount = 1.00
            simulateFailure = $false
        } | ConvertTo-Json -Compress

        try {
            $headers = @{
                "Idempotency-Key" = "smoke-readiness-$studentId-$enrollmentId"
            }
            $response = Invoke-WebRequest -Uri $url -Method POST -Body $payload -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 30
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK]  POST $url -> 200" -ForegroundColor Green
                return @{
                    studentId = $studentId
                    enrollmentId = $enrollmentId
                    payment = ($response.Content | ConvertFrom-Json)
                }
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host "[ERR] POST $url -> $($_.Exception.Message)" -ForegroundColor Red
                Write-ComposeDiagnostics
                throw
            }
            Start-Sleep -Seconds 3
        }
    }

    throw "Payment write readiness failed after retries: $url"
}

function Test-PaymentNotificationReadiness {
    param(
        [string]$BaseUrl,
        [int]$Attempts = 8
    )

    $paymentResult = Test-PaymentWriteReadiness -BaseUrl $BaseUrl -Attempts $Attempts
    $studentId = $paymentResult.studentId
    $paymentId = $paymentResult.payment.paymentId
    $url = "$BaseUrl/students/$studentId/notifications"

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -TimeoutSec 20
            if ($response.StatusCode -eq 200) {
                $notifications = $response.Content | ConvertFrom-Json
                $match = $notifications | Where-Object { $_.paymentId -eq $paymentId } | Select-Object -First 1
                if ($match) {
                    Write-Host "[OK]  payment event consumed by notification-service for payment $paymentId" -ForegroundColor Green
                    return
                }
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host "[ERR] GET $url -> $($_.Exception.Message)" -ForegroundColor Red
                Write-ComposeDiagnostics
                throw
            }
        }

        if ($i -eq $Attempts) {
            Write-ComposeDiagnostics
            throw "notification-service did not expose notification for payment $paymentId after $Attempts attempts"
        }
        Start-Sleep -Seconds 3
    }
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

Write-Step "Validate payment write path"
Test-PaymentWriteReadiness -BaseUrl $GatewayBaseUrl -Attempts $EndpointRetryAttempts

Write-Step "Validate payment notification async path"
Test-PaymentNotificationReadiness -BaseUrl $GatewayBaseUrl -Attempts $EndpointRetryAttempts

Write-Host ""
Write-Host "Gateway smoke CI test completed successfully." -ForegroundColor Green
