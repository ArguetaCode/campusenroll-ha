param(
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://campusenroll-api-gateway:8080",
    [string]$TestProfile = "smoke",
    [string]$K6Vus = "",
    [string]$K6Duration = "",
    [string]$K6ThresholdFailureRate = "",
    [string]$K6ThresholdP95Duration = "",
    [string]$K6ThresholdChecksRate = "",
    [switch]$IncludeNotificationCheck,
    [switch]$SkipGatewayPrecheck,
    [string]$GatewayHostBaseUrl = "http://localhost:8080",
    [int]$ReadinessRetryAttempts = 12,
    [string]$K6Script = "load-test.js",
    [string]$ArtifactsDir = "artifacts/k6"
)

$ErrorActionPreference = "Stop"
$env:COMPOSE_IGNORE_ORPHANS = "true"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Set-GatewayPortFromBaseUrl {
    param([string]$BaseUrl)

    try {
        $uri = [System.Uri]$BaseUrl
        if ($uri.Port -gt 0 -and $uri.Port -ne 80 -and $uri.Port -ne 443) {
            $env:GATEWAY_PORT = [string]$uri.Port
            Write-Host "[OK]  Compose GATEWAY_PORT set to $($env:GATEWAY_PORT) from GatewayHostBaseUrl" -ForegroundColor Green
        }
    } catch {
        Write-Host "[WARNING] Could not parse GatewayHostBaseUrl '$BaseUrl' to derive GATEWAY_PORT." -ForegroundColor Yellow
    }
}

function Invoke-Compose {
    param([string[]]$ComposeArgs)
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

function Test-Endpoint200 {
    param(
        [string]$Url,
        [int]$Attempts = 12
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
                throw "Endpoint did not return 200 after $Attempts attempts: $Url. $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 3
        }
    }
}

function Test-PaymentWriteReadiness {
    param(
        [string]$BaseUrl,
        [int]$Attempts = 12
    )

    $url = "$BaseUrl/api/enrollments"
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $suffix = "$(Get-Date -Format 'yyyyMMddHHmmssfff')-$i"
            $student = Invoke-RestMethod -Uri "$BaseUrl/students" -Method POST -ContentType "application/json" -TimeoutSec 30 -Body (@{
                fullName = "K6 Readiness $suffix"
                email = "k6-readiness-$suffix@campusenroll.local"
                status = "ACTIVE"
            } | ConvertTo-Json -Compress)
            $course = Invoke-RestMethod -Uri "$BaseUrl/courses" -Method POST -ContentType "application/json" -TimeoutSec 30 -Body (@{
                courseCode = "K6-$suffix"
                name = "K6 Readiness Course $suffix"
                description = "K6 payment readiness"
                status = "ACTIVE"
            } | ConvertTo-Json -Compress)
            $section = Invoke-RestMethod -Uri "$BaseUrl/sections" -Method POST -ContentType "application/json" -TimeoutSec 30 -Body (@{
                courseId = $course.id
                sectionCode = "K6-$suffix"
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
            $response = Invoke-WebRequest -Uri $url -Method POST -Body $payload -ContentType "application/json" -UseBasicParsing -TimeoutSec 30
            if ($response.StatusCode -eq 200) {
                $enrollment = $response.Content | ConvertFrom-Json
                Write-Host "[OK]  POST $url with valid payment -> 200" -ForegroundColor Green
                return @{
                    studentId = $student.id
                    enrollmentId = $enrollment.id
                    payment = @{ paymentId = $enrollment.paymentReference }
                }
            }
        } catch {
            if ($i -eq $Attempts) {
                throw "Enrollment payment readiness failed after $Attempts attempts: $url. $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 3
        }
    }
}

function Test-PaymentNotificationReadiness {
    param(
        [string]$BaseUrl,
        [int]$Attempts = 12
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
                throw "Notification readiness query failed after $Attempts attempts: $url. $($_.Exception.Message)"
            }
        }

        if ($i -eq $Attempts) {
            throw "notification-service did not expose notification for payment $paymentId after $Attempts attempts"
        }
        Start-Sleep -Seconds 3
    }
}

function Test-K6SummaryArtifact {
    param([string]$SummaryPath)

    if (-not (Test-Path -LiteralPath $SummaryPath)) {
        throw "k6 summary artifact was not created: $SummaryPath"
    }

    try {
        $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
    } catch {
        throw "k6 summary artifact is not valid JSON: $SummaryPath"
    }

    if (-not $summary.metrics) {
        throw "k6 summary artifact is missing metrics: $SummaryPath"
    }

    $metricNames = $summary.metrics.PSObject.Properties.Name
    $requiredMetrics = @("http_reqs", "http_req_duration", "http_req_failed", "checks", "iterations")
    foreach ($metricName in $requiredMetrics) {
        if ($metricNames -notcontains $metricName) {
            throw "k6 summary artifact is missing metric '$metricName': $SummaryPath"
        }
    }

    $thresholdMetrics = @("http_req_failed", "http_req_duration", "checks")
    foreach ($metricName in $thresholdMetrics) {
        $metric = $summary.metrics.PSObject.Properties[$metricName].Value
        if (-not $metric.thresholds) {
            throw "k6 summary artifact is missing thresholds for metric '$metricName': $SummaryPath"
        }

        if ($metric.thresholds.PSObject.Properties.Count -eq 0) {
            throw "k6 summary artifact has an empty thresholds block for metric '$metricName': $SummaryPath"
        }
    }

    Write-Host "[OK]  Summary JSON validated: $SummaryPath" -ForegroundColor Green
}

function Test-DirectoryWritable {
    param([string]$DirectoryPath)

    $probePath = Join-Path $DirectoryPath ".write-probe"
    try {
        "ok" | Set-Content -LiteralPath $probePath -NoNewline
        Remove-Item -LiteralPath $probePath -Force
    } catch {
        throw "Directory is not writable: $DirectoryPath. $($_.Exception.Message)"
    }
}

Write-Host "CampusEnroll-HA k6 Gateway CI Runner" -ForegroundColor Yellow
Write-Host "Compose file: $ComposeFile"
Write-Host "Gateway URL:  $GatewayBaseUrl"
Write-Host "Host URL:     $GatewayHostBaseUrl"
Write-Host "Profile:      $TestProfile"
Write-Host "Script:       $K6Script"
Write-Host "Artifacts:    $ArtifactsDir"
Set-GatewayPortFromBaseUrl -BaseUrl $GatewayHostBaseUrl
Write-Warning "k6 smoke scripts create test data in the configured environment. Use only disposable/local/CI databases."
Write-Host "Allowed k6 profile in current project phase: smoke" -ForegroundColor Yellow

$normalizedTestProfile = $TestProfile.ToLowerInvariant()
if ($normalizedTestProfile -ne "smoke") {
    throw "[ERROR] $TestProfile profile is disabled in current project phase. Only 'smoke' is allowed for CI/demo."
}

if ($K6Vus -ne "") {
    throw "[ERROR] K6_VUS override is disabled in current project phase. Smoke is fixed at 5 VUs."
}

if ($K6Duration -ne "") {
    throw "[ERROR] K6_DURATION override is disabled in current project phase. Smoke is fixed at 20s."
}

$allowedK6Scripts = @("load-test.js", "enrollment-flow-smoke.js")
if ($allowedK6Scripts -notcontains $K6Script) {
    throw "[ERROR] k6 script '$K6Script' is not allowed in CI/demo smoke mode."
}

if ($K6Script -eq "enrollment-flow-smoke.js") {
    Write-Warning "enrollment-flow-smoke.js creates real test rows for student, course, section, enrollment, payment, and notification validation."
} else {
    Write-Warning "load-test.js creates real test payment rows for smoke validation."
}

if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

$normalizedArtifactsDir = $ArtifactsDir.Replace("\", "/").TrimEnd("/")
if ($normalizedArtifactsDir -ne "artifacts/k6") {
    throw "ArtifactsDir must remain 'artifacts/k6' because docker-compose.yml mounts './artifacts/k6' into the k6 container."
}

$hostScriptPath = Join-Path "tests" $K6Script
if (-not (Test-Path -LiteralPath $hostScriptPath)) {
    throw "k6 script not found: $hostScriptPath"
}

if (-not $SkipGatewayPrecheck) {
    Write-Step "Run gateway smoke precheck (non-destructive)"
    $powerShellExe = (Get-Process -Id $PID).Path
    $gatewaySmokeScript = Join-Path $PSScriptRoot "gateway-smoke-ci.ps1"
    & $powerShellExe -NoProfile -File $gatewaySmokeScript -ComposeFile $ComposeFile -GatewayBaseUrl $GatewayHostBaseUrl
    if ($LASTEXITCODE -ne 0) {
        throw "gateway-smoke-ci.ps1 failed"
    }
} else {
    Write-Step "Skipping gateway precheck because -SkipGatewayPrecheck was provided"
}

$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactRoot = (Resolve-Path -LiteralPath ".").Path
$hostArtifactsDir = Join-Path $artifactRoot $ArtifactsDir
New-Item -ItemType Directory -Path $hostArtifactsDir -Force | Out-Null
Test-DirectoryWritable -DirectoryPath $hostArtifactsDir
Write-Host "[OK]  Host artifacts directory is ready: $hostArtifactsDir" -ForegroundColor Green

Write-Step "Validate gateway payment readiness before k6"
try {
    Test-Endpoint200 -Url "$GatewayHostBaseUrl/payments" -Attempts $ReadinessRetryAttempts
    Test-PaymentNotificationReadiness -BaseUrl $GatewayHostBaseUrl -Attempts $ReadinessRetryAttempts
} catch {
    Write-ComposeDiagnostics
    throw
}

Write-Step "Run k6 against gateway"
$summaryFileInContainer = "/artifacts/summary-$runId.json"
$resultsFileInContainer = "/artifacts/results-$runId.json"

$runArgs = @(
    "--profile", "testing", "run", "--rm"
)

if ($IsLinux) {
    $hostUid = (& id -u).Trim()
    if ($LASTEXITCODE -ne 0 -or $hostUid -eq "") {
        throw "Unable to resolve host UID for k6 artifact ownership."
    }

    $hostGid = (& id -g).Trim()
    if ($LASTEXITCODE -ne 0 -or $hostGid -eq "") {
        throw "Unable to resolve host GID for k6 artifact ownership."
    }

    $runArgs += @("--user", "${hostUid}:${hostGid}")
    Write-Host "[OK]  k6 container will write artifacts as host user ${hostUid}:${hostGid}" -ForegroundColor Green
}

$runArgs += @(
    "-e", "GATEWAY_BASE_URL=$GatewayBaseUrl",
    "-e", "TEST_PROFILE=$normalizedTestProfile",
    "-e", "K6_IDEMPOTENCY_KEY_PREFIX=k6-$normalizedTestProfile-$runId",
    "k6", "run",
    "--summary-export", $summaryFileInContainer,
    "--out", "json=$resultsFileInContainer"
)

if ($K6ThresholdFailureRate -ne "") {
    $runArgs += @("-e", "K6_THRESHOLD_FAILURE_RATE=$K6ThresholdFailureRate")
}

if ($K6ThresholdP95Duration -ne "") {
    $runArgs += @("-e", "K6_THRESHOLD_P95_DURATION=$K6ThresholdP95Duration")
}

if ($K6ThresholdChecksRate -ne "") {
    $runArgs += @("-e", "K6_THRESHOLD_CHECKS_RATE=$K6ThresholdChecksRate")
}

if ($IncludeNotificationCheck) {
    $runArgs += @("-e", "INCLUDE_NOTIFICATION_CHECK=true")
}

$runArgs += @("/scripts/$K6Script")

$k6RunSucceeded = $true
$k6RunError = $null
try {
    Invoke-Compose -ComposeArgs $runArgs
} catch {
    $k6RunSucceeded = $false
    $k6RunError = $_
    Write-ComposeDiagnostics
}

$summaryPath = Join-Path $hostArtifactsDir "summary-$runId.json"
$resultsPath = Join-Path $hostArtifactsDir "results-$runId.json"

if (-not (Test-Path -LiteralPath $summaryPath) -and -not $k6RunSucceeded) {
    throw "k6 run failed before the summary artifact was created: $summaryPath. Original error: $k6RunError"
}

Test-K6SummaryArtifact -SummaryPath $summaryPath

if (-not (Test-Path -LiteralPath $resultsPath)) {
    if (-not $k6RunSucceeded) {
        throw "k6 run failed before the results artifact was created: $resultsPath. Original error: $k6RunError"
    }

    throw "k6 results artifact was not created: $resultsPath"
}

if (-not $k6RunSucceeded) {
    throw "k6 run failed after artifact validation. Original error: $k6RunError"
}

Write-Host ""
Write-Host "k6 gateway CI run completed successfully." -ForegroundColor Green
Write-Host "Summary artifact: $summaryPath"
Write-Host "Results artifact: $resultsPath"
