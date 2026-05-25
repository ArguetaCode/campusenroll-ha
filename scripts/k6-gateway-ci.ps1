param(
    [string]$ComposeFile = "docker-compose.yml",
    [string]$GatewayBaseUrl = "http://campusenroll-api-gateway:8080",
    [ValidateSet("smoke", "baseline")]
    [string]$TestProfile = "smoke",
    [string]$K6Vus = "",
    [string]$K6Duration = "",
    [string]$K6ThresholdFailureRate = "",
    [string]$K6ThresholdP95Duration = "",
    [string]$K6ThresholdChecksRate = "",
    [switch]$IncludeNotificationCheck,
    [switch]$SkipGatewayPrecheck,
    [string]$ArtifactsDir = "artifacts/k6"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    & docker compose -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($ComposeArgs -join ' ')"
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

Write-Host "CampusEnroll-HA k6 Gateway CI Runner" -ForegroundColor Yellow
Write-Host "Compose file: $ComposeFile"
Write-Host "Gateway URL:  $GatewayBaseUrl"
Write-Host "Profile:      $TestProfile"
Write-Host "Artifacts:    $ArtifactsDir"

if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

if (-not $SkipGatewayPrecheck) {
    Write-Step "Run gateway smoke precheck (non-destructive)"
    $powerShellExe = (Get-Process -Id $PID).Path
    $gatewaySmokeScript = Join-Path $PSScriptRoot "gateway-smoke-ci.ps1"
    & $powerShellExe -NoProfile -File $gatewaySmokeScript -ComposeFile $ComposeFile -GatewayBaseUrl "http://localhost:8080"
    if ($LASTEXITCODE -ne 0) {
        throw "gateway-smoke-ci.ps1 failed"
    }
} else {
    Write-Step "Skipping gateway precheck because -SkipGatewayPrecheck was provided"
}

Write-Step "Run k6 against gateway"
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactRoot = Resolve-Path -LiteralPath "."
$hostArtifactsDir = Join-Path $artifactRoot $ArtifactsDir
New-Item -ItemType Directory -Path $hostArtifactsDir -Force | Out-Null

$summaryFileInContainer = "/artifacts/summary-$runId.json"
$resultsFileInContainer = "/artifacts/results-$runId.json"

$runArgs = @(
    "--profile", "testing", "run", "--rm",
    "-e", "GATEWAY_BASE_URL=$GatewayBaseUrl",
    "-e", "TEST_PROFILE=$TestProfile",
    "k6", "run",
    "--summary-export", $summaryFileInContainer,
    "--out", "json=$resultsFileInContainer"
)

if ($K6Vus -ne "") {
    $runArgs += @("-e", "K6_VUS=$K6Vus")
}

if ($K6Duration -ne "") {
    $runArgs += @("-e", "K6_DURATION=$K6Duration")
}

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

$runArgs += @("/scripts/load-test.js")

Invoke-Compose -ComposeArgs $runArgs

$summaryPath = Join-Path $hostArtifactsDir "summary-$runId.json"
$resultsPath = Join-Path $hostArtifactsDir "results-$runId.json"

Test-K6SummaryArtifact -SummaryPath $summaryPath

if (-not (Test-Path -LiteralPath $resultsPath)) {
    throw "k6 results artifact was not created: $resultsPath"
}

Write-Host ""
Write-Host "k6 gateway CI run completed successfully." -ForegroundColor Green
Write-Host "Summary artifact: $summaryPath"
Write-Host "Results artifact: $resultsPath"
