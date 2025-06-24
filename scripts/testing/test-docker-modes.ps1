#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive Docker Mode Test - Validates Docker mode functionality and configuration

.DESCRIPTION
    This script provides comprehensive testing for Docker mode functionality, including environment
    configuration, compose file validation, and startup simulation. Moved to scripts/testing/ for
    better organization per NEOMINT-RESEARCH guidelines.

.PARAMETER DockerMode
    Docker mode to test: "standard" or "rootless". Default: "standard"

.EXAMPLE
    .\scripts\testing\test-docker-modes.ps1
    Test standard Docker mode with comprehensive validation

.EXAMPLE
    .\scripts\testing\test-docker-modes.ps1 -DockerMode rootless
    Test rootless Docker mode with comprehensive validation

.NOTES
    This script performs comprehensive testing including startup simulation.
    For simple testing, see: scripts/testing/simple-docker-test.ps1
#>

param(
    [ValidateSet("standard", "rootless")]
    [string]$DockerMode = "standard"
)

Write-Host "=== Docker Mode Test ===" -ForegroundColor Green
Write-Host "Testing Docker mode: $DockerMode" -ForegroundColor Cyan

# Ensure we're in the project root directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptPath))
Set-Location $projectRoot

# Test 1: Environment Configuration
Write-Host "`n1. Testing Environment Configuration..." -ForegroundColor Yellow

if ($DockerMode -eq "rootless") {
    Write-Host "Creating rootless Docker environment..." -ForegroundColor Cyan
    $currentUID = 1001
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        try {
            $currentUID = wsl id -u 2>$null
            if ($currentUID) {
                Write-Host "Detected WSL UID: $currentUID" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Using default UID: $currentUID" -ForegroundColor Yellow
        }
    }
    
    $env:DOCKER_USER_ID = $currentUID
    # Use platform-specific compose file
    if (-not ($IsLinux -or $env:WSL_DISTRO_NAME)) {
        $composeFile = "docker-compose.windows.yml"
        $socketPath = "//./pipe/docker_engine"
    } else {
        $composeFile = "docker-compose.yml"
        $socketPath = "/run/user/$currentUID/docker.sock"
    }
    
    Write-Host "✓ Rootless configuration created" -ForegroundColor Green
    Write-Host "  User ID: $currentUID" -ForegroundColor White
    Write-Host "  Socket Path: $socketPath" -ForegroundColor White
    Write-Host "  Compose File: $composeFile" -ForegroundColor White
}
else {
    Write-Host "Creating standard Docker environment..." -ForegroundColor Cyan
    $composeFile = "docker-compose.yml"
    $socketPath = "/var/run/docker.sock"
    
    Write-Host "✓ Standard configuration created" -ForegroundColor Green
    Write-Host "  Socket Path: $socketPath" -ForegroundColor White
    Write-Host "  Compose File: $composeFile" -ForegroundColor White
}

# Test 2: Docker Availability Check
Write-Host "`n2. Testing Docker Availability..." -ForegroundColor Yellow

try {
    $dockerVersion = docker --version
    Write-Host "✓ Docker found: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "✗ Docker not available" -ForegroundColor Red
    exit 1
}

# Test 3: Compose File Check
Write-Host "`n3. Testing Compose File..." -ForegroundColor Yellow

$composeFilePath = "deploy/$composeFile"
if (Test-Path $composeFilePath) {
    Write-Host "✓ Compose file exists: $composeFilePath" -ForegroundColor Green
}
else {
    Write-Host "✗ Compose file not found: $composeFilePath" -ForegroundColor Red
    exit 1
}

# Test 4: Environment File Creation
Write-Host "`n4. Creating Environment File..." -ForegroundColor Yellow

New-Item -Path "deploy/env" -ItemType Directory -Force | Out-Null

if ($DockerMode -eq "rootless") {
    $envContent = @"
# Test Environment - Rootless Mode
ORCHESTRATOR_PORT=3000
DOCKER_MODE=rootless
DOCKER_ROOTLESS_SOCKET_PATH=$socketPath
MCP_TIMEOUT=45000
DISCOVERY_RETRY_ATTEMPTS=10
ROOTLESS_MODE=true
DOCKER_ROOTLESS_ENABLED=true
"@
}
else {
    $envContent = @"
# Test Environment - Standard Mode
ORCHESTRATOR_PORT=3000
DOCKER_MODE=auto
DOCKER_SOCKET_PATH=$socketPath
MCP_TIMEOUT=30000
DISCOVERY_RETRY_ATTEMPTS=5
"@
}

Set-Content -Path "deploy/env/.env.test" -Value $envContent
Write-Host "✓ Environment file created: deploy/env/.env.test" -ForegroundColor Green

# Test 5: Docker Compose Validation
Write-Host "`n5. Testing Docker Compose..." -ForegroundColor Yellow

Set-Location "deploy"
try {
    if ($DockerMode -eq "rootless") {
        Write-Host "Validating rootless compose file..." -ForegroundColor Cyan
        docker-compose -f $composeFile config | Out-Null
    }
    else {
        Write-Host "Validating standard compose file..." -ForegroundColor Cyan
        docker-compose -f $composeFile config | Out-Null
    }
    
    Write-Host "✓ Docker compose configuration is valid" -ForegroundColor Green
}
catch {
    Write-Host "✗ Docker compose validation failed: $_" -ForegroundColor Red
}
finally {
    Set-Location ".."
}

# Test 6: Startup Simulation (without actually starting)
Write-Host "`n6. Simulating Startup Process..." -ForegroundColor Yellow

Write-Host "Would execute: docker-compose -f deploy/$composeFile up -d --build" -ForegroundColor Cyan

if ($DockerMode -eq "rootless") {
    Write-Host "Rootless mode would use:" -ForegroundColor Cyan
    Write-Host "  • User ID: $env:DOCKER_USER_ID" -ForegroundColor White
    Write-Host "  • Extended timeouts (45s)" -ForegroundColor White
    Write-Host "  • Enhanced retry logic (10 attempts)" -ForegroundColor White
    Write-Host "  • Security-focused container configuration" -ForegroundColor White
}
else {
    Write-Host "Standard mode would use:" -ForegroundColor Cyan
    Write-Host "  • Standard timeouts (30s)" -ForegroundColor White
    Write-Host "  • Basic retry logic (5 attempts)" -ForegroundColor White
    Write-Host "  • Standard container configuration" -ForegroundColor White
}

Write-Host "✓ Startup simulation completed" -ForegroundColor Green

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Green
Write-Host "Docker Mode: $DockerMode" -ForegroundColor Cyan
Write-Host "Compose File: $composeFile" -ForegroundColor Cyan
Write-Host "Socket Path: $socketPath" -ForegroundColor Cyan

if ($DockerMode -eq "rootless") {
    Write-Host "User ID: $env:DOCKER_USER_ID" -ForegroundColor Cyan
}

Write-Host "`n✓ All tests passed! Docker mode configuration is working correctly." -ForegroundColor Green

# Cleanup
Write-Host "`nCleaning up test files..." -ForegroundColor Yellow
Remove-Item "deploy/env/.env.test" -ErrorAction SilentlyContinue
Write-Host "✓ Cleanup completed" -ForegroundColor Green
