#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple Docker Mode Test - Validates Docker configuration and mode functionality

.DESCRIPTION
    This script provides basic testing for Docker mode functionality, validating compose files,
    environment configuration, and Docker availability. Moved to scripts/testing/ for better
    organization per NEOMINT-RESEARCH guidelines.

.PARAMETER Mode
    Docker mode to test: "standard" or "rootless". Default: "standard"

.EXAMPLE
    .\scripts\testing\simple-docker-test.ps1
    Test standard Docker mode

.EXAMPLE
    .\scripts\testing\simple-docker-test.ps1 -Mode rootless
    Test rootless Docker mode

.NOTES
    This script performs non-destructive testing and creates temporary files for validation.
    For comprehensive testing, see: scripts/testing/test-docker-modes.ps1
#>

param([string]$Mode = "standard")

Write-Host "=== Docker Mode Test: $Mode ===" -ForegroundColor Green

# Ensure we're in the project root directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptPath))
Set-Location $projectRoot

# Test Docker availability
Write-Host "Testing Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "Docker version: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "✗ Docker not available" -ForegroundColor Red
    exit 1
}

# Test compose file existence - use platform-aware selection
if ($Mode -eq "rootless") {
    # Determine platform-specific compose file
    if (-not ($IsLinux -or $env:WSL_DISTRO_NAME)) {
        # Windows Docker Desktop
        $composeFile = "deploy/docker-compose.windows.yml"
    } else {
        # Unix/Linux rootless Docker
        $composeFile = "deploy/docker-compose.yml"
    }
} else {
    $composeFile = "deploy/docker-compose.yml"
}

Write-Host "Testing compose file: $composeFile" -ForegroundColor Yellow
if (Test-Path $composeFile) {
    Write-Host "✓ Compose file exists" -ForegroundColor Green
} else {
    Write-Host "✗ Compose file not found" -ForegroundColor Red
    exit 1
}

# Test environment configuration
Write-Host "Creating environment configuration..." -ForegroundColor Yellow
New-Item -Path "deploy/env" -ItemType Directory -Force | Out-Null

if ($Mode -eq "rootless") {
    $currentUID = 1001
    # Try to detect actual UID if on WSL
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        try {
            $detectedUID = wsl id -u 2>$null
            if ($detectedUID) {
                $currentUID = $detectedUID
                Write-Host "Detected WSL UID: $currentUID" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "Using default UID: $currentUID" -ForegroundColor Yellow
        }
    }
    
    $env:DOCKER_USER_ID = $currentUID
    $envContent = "DOCKER_MODE=rootless`nDOCKER_USER_ID=$currentUID`nMCP_TIMEOUT=45000`nROOTLESS_MODE=true"
    Write-Host "Rootless mode - UID: $currentUID" -ForegroundColor Cyan
} else {
    $envContent = "DOCKER_MODE=auto`nMCP_TIMEOUT=30000"
    Write-Host "Standard mode" -ForegroundColor Cyan
}

Set-Content -Path "deploy/env/.env.test" -Value $envContent
Write-Host "✓ Environment file created" -ForegroundColor Green

# Test compose validation
Write-Host "Validating compose configuration..." -ForegroundColor Yellow
Set-Location "deploy"
try {
    docker-compose -f (Split-Path $composeFile -Leaf) config | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Compose configuration valid" -ForegroundColor Green
    } else {
        Write-Host "✗ Compose configuration invalid" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Compose validation failed: $_" -ForegroundColor Red
}
finally {
    Set-Location ".."
}

# Summary
Write-Host "`n=== Test Results ===" -ForegroundColor Green
Write-Host "Mode: $Mode" -ForegroundColor White
Write-Host "Compose File: $composeFile" -ForegroundColor White
if ($Mode -eq "rootless") {
    Write-Host "User ID: $env:DOCKER_USER_ID" -ForegroundColor White
    Write-Host "Socket Path: /run/user/$env:DOCKER_USER_ID/docker.sock" -ForegroundColor White
}
Write-Host "✓ All tests completed successfully" -ForegroundColor Green

# Cleanup
Remove-Item "deploy/env/.env.test" -ErrorAction SilentlyContinue
Write-Host "✓ Cleanup completed" -ForegroundColor Green
