param(
    [string]$StackName = "campusenroll",
    [string]$EnvFile = ".\\env\\swarm.env",
    [string]$ComposeFile = ".\\docker-stack.yml",
    [switch]$BuildImages
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Env file not found: $EnvFile. Copy env/swarm.env.example to env/swarm.env first."
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

$state = docker info --format "{{.Swarm.LocalNodeState}}" 2>$null
if ($state -ne "active") {
    throw "Swarm is not active on this node. Run scripts/swarm/init-manager.ps1 first."
}

function Import-DotEnv {
    param([string]$Path)
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            [Environment]::SetEnvironmentVariable($parts[0], $parts[1])
        }
    }
}

Import-DotEnv -Path $EnvFile

if ($BuildImages) {
    $builds = @(
        @{ Context = "..\\student-service"; Image = $env:STUDENT_SERVICE_IMAGE },
        @{ Context = "..\\course-service"; Image = $env:COURSE_SERVICE_IMAGE },
        @{ Context = "..\\billing-service"; Image = $env:BILLING_SERVICE_IMAGE },
        @{ Context = "..\\notification"; Image = $env:NOTIFICATION_SERVICE_IMAGE },
        @{ Context = "..\\enrollment-service\\enrollment-service\\enrollment-service"; Image = $env:ENROLLMENT_SERVICE_IMAGE },
        @{ Context = "."; Dockerfile = ".\\api-gateway\\Dockerfile.swarm"; Image = $env:API_GATEWAY_IMAGE }
    )

    foreach ($build in $builds) {
        if (-not $build.Image) {
            throw "One or more image variables are missing in $EnvFile."
        }

        if ($build.Dockerfile) {
            docker build -f $build.Dockerfile -t $build.Image $build.Context
        } else {
            docker build -t $build.Image $build.Context
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed building image $($build.Image)."
        }
    }
}

docker stack deploy --compose-file $ComposeFile --with-registry-auth $StackName
if ($LASTEXITCODE -ne 0) {
    throw "docker stack deploy failed."
}

Write-Host "Stack deployed. Current services:" -ForegroundColor Green
docker stack services $StackName

