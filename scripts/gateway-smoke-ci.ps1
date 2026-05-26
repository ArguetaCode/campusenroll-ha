param(
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://localhost:8080",
    [int]$ContainerWaitAttempts = 30,
    [int]$EndpointRetryAttempts = 8,
    [int]$EndpointTimeoutSeconds = 10,
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

function Invoke-FlywayMigrations {
    $composeArgs = @("--profile", "db-migration", "run", "--rm", "campusenroll-flyway")
    $output = & docker compose -f $ComposeFile @composeArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0) {
        $outputText = ($output | ForEach-Object { "$_" }) -join "`n"
        if ($outputText -match "Found non-empty schema\(s\)|schema history table|flyway_schema_history") {
            Write-Host ""
            Write-Host "[WARNING] Existing local database detected without Flyway history table." -ForegroundColor Yellow
            Write-Host "[WARNING] This usually indicates a pre-Flyway local volume." -ForegroundColor Yellow
            Write-Host "[WARNING] CI environments with clean volumes should not hit this issue." -ForegroundColor Yellow
            Write-Host "[WARNING] Use a clean local PostgreSQL volume if Flyway-managed migrations are required." -ForegroundColor Yellow
        }

        throw "docker compose failed: $($composeArgs -join ' ')"
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
                Write-ComposeDiagnostics
                throw "$Label returned HTTP $($response.StatusCode)"
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label $Label) -ForegroundColor Red
                Write-ComposeDiagnostics
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
                    Write-ComposeDiagnostics
                    throw "$Label health returned HTTP $($response.StatusCode)"
                }
                Start-Sleep -Seconds 2
                continue
            }

            try {
                $content = if ($response.Content -is [byte[]]) {
                    [System.Text.Encoding]::UTF8.GetString($response.Content)
                } else {
                    $response.Content
                }
                $payload = $content | ConvertFrom-Json
            } catch {
                Write-Host "[ERROR] $Label health returned invalid JSON" -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "$Label health returned invalid JSON"
            }

            if ($payload.status -ne "UP") {
                Write-Host "[ERROR] $Label health returned unexpected payload: $content" -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "$Label health returned unexpected payload"
            }

            Write-Host "[OK]  $Label health -> UP" -ForegroundColor Green
            return
        } catch {
            if ($i -eq $Attempts) {
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label "$Label health endpoint") -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "$Label health failed after $Attempts attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Test-PaymentWriteReadiness {
    param(
        [string]$BaseUrl,
        [int]$Attempts = 8
    )

    $url = "$BaseUrl/api/enrollments"
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $suffix = "$(Get-Date -Format 'yyyyMMddHHmmssfff')-$i"
            $student = Invoke-RestMethod -Uri "$BaseUrl/students" -Method POST -ContentType "application/json" -TimeoutSec 15 -Body (@{
                fullName = "Smoke Payment $suffix"
                email = "smoke-payment-$suffix@campusenroll.local"
                status = "ACTIVE"
            } | ConvertTo-Json -Compress)
            $course = Invoke-RestMethod -Uri "$BaseUrl/courses" -Method POST -ContentType "application/json" -TimeoutSec 15 -Body (@{
                courseCode = "SP-$suffix"
                name = "Smoke Payment Course $suffix"
                description = "Payment readiness"
                status = "ACTIVE"
            } | ConvertTo-Json -Compress)
            $section = Invoke-RestMethod -Uri "$BaseUrl/sections" -Method POST -ContentType "application/json" -TimeoutSec 15 -Body (@{
                courseId = $course.id
                sectionCode = "SP-$suffix"
                maxCapacity = 1
                status = "ACTIVE"
                schedules = @()
            } | ConvertTo-Json -Compress)
            $payload = @{
                studentId = $student.id
                sectionId = $section.id
                amount = 1.00
                simulatePaymentFailure = $false
            } | ConvertTo-Json -Compress

            $response = Invoke-WebRequest -Uri $url -Method POST -Body $payload -ContentType "application/json" -UseBasicParsing -TimeoutSec 15
            if ($response.StatusCode -eq 200) {
                $enrollment = $response.Content | ConvertFrom-Json
                Write-Host "[OK]  POST $url with valid payment -> 200" -ForegroundColor Green
                return @{
                    studentId = $student.id
                    enrollmentId = $enrollment.id
                    payment = @{ paymentId = $enrollment.paymentReference }
                }
            }

            if ($i -eq $Attempts) {
                Write-Host "[ERROR] payment write path returned HTTP $($response.StatusCode)" -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "payment write path returned HTTP $($response.StatusCode)"
            }
        } catch {
            if ($i -eq $Attempts) {
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label "payment write path") -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "payment write path failed after $Attempts attempts"
            }
            Start-Sleep -Seconds 2
        }
    }

    throw "Enrollment payment readiness failed after retries: $url"
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
            $response = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -TimeoutSec 10
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
                Write-Host (Get-WebFailureMessage -ErrorRecord $_ -Label "notification readiness endpoint") -ForegroundColor Red
                Write-ComposeDiagnostics
                throw "notification readiness endpoint failed after $Attempts attempts"
            }
        }

        if ($i -eq $Attempts) {
            Write-ComposeDiagnostics
            throw "notification-service did not expose notification for payment $paymentId after $Attempts attempts"
        }
        Start-Sleep -Seconds 2
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
    Invoke-FlywayMigrations
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

Write-Step "Validate enrollment payment write path"
Test-PaymentWriteReadiness -BaseUrl $GatewayBaseUrl -Attempts $EndpointRetryAttempts

Write-Step "Validate payment notification async path"
Test-PaymentNotificationReadiness -BaseUrl $GatewayBaseUrl -Attempts $EndpointRetryAttempts

Write-Host ""
Write-Host "Gateway smoke CI test completed successfully." -ForegroundColor Green
