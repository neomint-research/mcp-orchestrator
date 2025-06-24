# MCP Orchestrator - Rootless Docker Startup Script (PowerShell)
# This script automatically detects the current user's UID and starts the orchestrator in rootless mode
# Moved to scripts/deploy/ for better organization per NEOMINT-RESEARCH guidelines

param(
    [switch]$Build,
    [switch]$Detach,
    [string[]]$AdditionalArgs = @()
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "MCP Orchestrator - Rootless Docker Setup" "Blue"
Write-ColorOutput "========================================" "Blue"

# Check if we're in the right directory
if (-not (Test-Path "deploy/docker-compose.yml") -and -not (Test-Path "deploy/docker-compose.windows.yml")) {
    Write-ColorOutput "Error: Docker Compose files not found. Please run this script from the project root." "Red"
    exit 1
}

# For Windows/WSL2, we need to handle UID differently
$CurrentUID = 1001  # Default fallback

# Try to get UID from WSL if available
try {
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $CurrentUID = wsl id -u
        Write-ColorOutput "Detected WSL user ID: $CurrentUID" "Green"
    } else {
        Write-ColorOutput "WSL not available, using default UID: $CurrentUID" "Yellow"
    }
} catch {
    Write-ColorOutput "Could not detect UID, using default: $CurrentUID" "Yellow"
}

# Check Docker availability
try {
    docker version | Out-Null
    Write-ColorOutput "Docker is available" "Green"
} catch {
    Write-ColorOutput "Error: Docker is not available or not running" "Red"
    exit 1
}

# Set environment variables
$env:DOCKER_USER_ID = $CurrentUID

Write-ColorOutput "Starting MCP Orchestrator in rootless mode..." "Blue"
Write-ColorOutput "User ID: $CurrentUID" "Blue"

# Change to deploy directory
Set-Location deploy

# Determine which Docker Compose file to use based on platform
$ComposeFile = "docker-compose.yml"  # Default for Unix/Linux
if (-not ($IsLinux -or $env:WSL_DISTRO_NAME)) {
    # Windows Docker Desktop
    $ComposeFile = "docker-compose.windows.yml"
    Write-ColorOutput "Using Windows Docker Desktop configuration" "Cyan"
} else {
    Write-ColorOutput "Using Unix/Linux rootless Docker configuration" "Cyan"
}

# Build arguments with platform-specific compose file
$DockerComposeArgs = @("-f", $ComposeFile, "up")

if ($Build) {
    Write-ColorOutput "Building and starting services..." "Yellow"
    $DockerComposeArgs += "--build"
}

if ($Detach) {
    Write-ColorOutput "Starting services in detached mode..." "Yellow"
    $DockerComposeArgs += "-d"
} else {
    Write-ColorOutput "Starting services..." "Yellow"
}

# Add any additional arguments
$DockerComposeArgs += $AdditionalArgs

# Start the services
try {
    & docker-compose @DockerComposeArgs
    
    if ($Detach) {
        Write-ColorOutput "Services started successfully!" "Green"
        Write-ColorOutput "Check status with: docker-compose ps" "Blue"
        Write-ColorOutput "View logs with: docker-compose logs -f" "Blue"
    }
} catch {
    Write-ColorOutput "Error starting services: $_" "Red"
    exit 1
}
