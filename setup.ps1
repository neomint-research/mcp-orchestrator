#!/usr/bin/env pwsh
# MCP Multi-Agent Orchestrator Setup Script
# One-click entry point for system initialization and startup

param(
    [switch]$SkipChecks,
    [switch]$DevMode,
    [string]$LogLevel = "INFO"
)

Write-Host "=== MCP Multi-Agent Orchestrator Setup ===" -ForegroundColor Green
Write-Host "Initializing system with NEOMINT-RESEARCH architecture..." -ForegroundColor Cyan

# Environment Checks
function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    
    # Check Docker
    try {
        $dockerVersion = docker --version
        Write-Host "✓ Docker found: $dockerVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Docker not found. Please install Docker Desktop." -ForegroundColor Red
        exit 1
    }
    
    # Check Docker Compose
    try {
        $composeVersion = docker-compose --version
        Write-Host "✓ Docker Compose found: $composeVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Docker Compose not found. Please install Docker Compose." -ForegroundColor Red
        exit 1
    }
    
    # Check Node.js
    try {
        $nodeVersion = node --version
        Write-Host "✓ Node.js found: $nodeVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Node.js not found. Please install Node.js 18+." -ForegroundColor Red
        exit 1
    }
}

# Environment Configuration
function Initialize-Environment {
    Write-Host "Setting up environment configuration..." -ForegroundColor Yellow
    
    # Create .env file if it doesn't exist
    if (-not (Test-Path "deploy/env/.env.core")) {
        Write-Host "Creating default environment configuration..." -ForegroundColor Cyan
        New-Item -Path "deploy/env" -ItemType Directory -Force | Out-Null
        
        $envContent = @"
# MCP Orchestrator Core Configuration
ORCHESTRATOR_PORT=3000
DISCOVERY_INTERVAL=30000
LOG_LEVEL=$LogLevel
DOCKER_SOCKET=/var/run/docker.sock
MCP_TIMEOUT=30000
HEALTH_CHECK_INTERVAL=60000
"@
        Set-Content -Path "deploy/env/.env.core" -Value $envContent
        Write-Host "✓ Environment configuration created" -ForegroundColor Green
    }
}

# System Startup
function Start-System {
    Write-Host "Starting MCP Multi-Agent Orchestrator system..." -ForegroundColor Yellow
    
    # Build and start containers
    Set-Location "deploy"
    
    if ($DevMode) {
        Write-Host "Starting in development mode..." -ForegroundColor Cyan
        docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
    }
    else {
        Write-Host "Starting in production mode..." -ForegroundColor Cyan
        docker-compose up --build -d
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ System started successfully" -ForegroundColor Green
        Write-Host "Orchestrator available at: http://localhost:3000" -ForegroundColor Cyan
    }
    else {
        Write-Host "✗ Failed to start system" -ForegroundColor Red
        exit 1
    }
    
    Set-Location ".."
}

# Main execution
try {
    if (-not $SkipChecks) {
        Test-Prerequisites
    }
    
    Initialize-Environment
    Start-System
    
    Write-Host "=== Setup Complete ===" -ForegroundColor Green
    Write-Host "Use 'scripts/health-check-all.sh' to verify all components are running" -ForegroundColor Cyan
    Write-Host "Use 'scripts/show-ports.sh' to see all exposed ports" -ForegroundColor Cyan
}
catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
