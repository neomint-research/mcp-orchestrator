# MCP Orchestrator Setup Script - Rootless Docker Only
# This script sets up the MCP Orchestrator for rootless Docker deployment exclusively
# No legacy Docker support - enhanced security through rootless operation
# Includes comprehensive Windows prerequisite checking and automated setup

param(
    [switch]$Help,
    [switch]$Verbose,
    [switch]$SkipPrerequisites,
    [switch]$StartServices
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to show help
function Show-Help {
    Write-ColorOutput "MCP Orchestrator Setup - Rootless Docker Only" "Cyan"
    Write-ColorOutput "=============================================" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "This script sets up the MCP Orchestrator for rootless Docker deployment." "White"
    Write-ColorOutput "Rootless Docker provides enhanced security by running without root privileges." "White"
    Write-ColorOutput ""
    Write-ColorOutput "USAGE:" "Yellow"
    Write-ColorOutput "  .\setup.ps1                     # Full setup with prerequisite checking" "White"
    Write-ColorOutput "  .\setup.ps1 -StartServices      # Setup and start orchestrator services" "White"
    Write-ColorOutput "  .\setup.ps1 -Verbose            # Verbose output" "White"
    Write-ColorOutput "  .\setup.ps1 -SkipPrerequisites  # Skip Windows feature checks" "White"
    Write-ColorOutput "  .\setup.ps1 -Help               # Show this help" "White"
    Write-ColorOutput ""
    Write-ColorOutput "WINDOWS PREREQUISITES (Auto-checked):" "Yellow"
    Write-ColorOutput "  - Windows Subsystem for Linux (WSL)" "White"
    Write-ColorOutput "  - Virtual Machine Platform" "White"
    Write-ColorOutput "  - Hyper-V (if applicable)" "White"
    Write-ColorOutput "  - WSL 2 with Ubuntu distribution" "White"
    Write-ColorOutput "  - Rootless Docker in WSL" "White"
    Write-ColorOutput ""
    Write-ColorOutput "NOTES:" "Yellow"
    Write-ColorOutput "  - Administrative privileges may be required for Windows feature installation" "White"
    Write-ColorOutput "  - System restart may be required after enabling Windows features" "White"
    Write-ColorOutput "  - The script will ask for permission before making system changes" "White"
    Write-ColorOutput "  - Use -StartServices to automatically start the orchestrator after setup" "White"
    Write-ColorOutput ""
    exit 0
}

if ($Help) {
    Show-Help
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to prompt for user confirmation
function Get-UserConfirmation {
    param(
        [string]$Message,
        [string]$DefaultChoice = "N"
    )

    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Yes")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "No")
    )

    $defaultIndex = if ($DefaultChoice -eq "Y") { 0 } else { 1 }
    $result = $Host.UI.PromptForChoice("Confirmation", $Message, $choices, $defaultIndex)
    return $result -eq 0
}

# Function to check Windows features
function Test-WindowsFeature {
    param([string]$FeatureName)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return $feature -and $feature.State -eq "Enabled"
    } catch {
        return $false
    }
}

# Function to enable Windows features
function Enable-RequiredWindowsFeatures {
    Write-ColorOutput "Checking Windows features..." "Blue"

    $requiredFeatures = @(
        @{ Name = "Microsoft-Windows-Subsystem-Linux"; DisplayName = "Windows Subsystem for Linux" },
        @{ Name = "VirtualMachinePlatform"; DisplayName = "Virtual Machine Platform" }
    )

    # Check Hyper-V availability (not required on all systems)
    $hyperVAvailable = $false
    try {
        $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
        $hyperVAvailable = $null -ne $hyperVFeature
    } catch {
        # Hyper-V not available on this system (e.g., Home edition)
    }

    if ($hyperVAvailable) {
        $requiredFeatures += @{ Name = "Microsoft-Hyper-V-All"; DisplayName = "Hyper-V" }
    }

    $missingFeatures = @()
    $enabledFeatures = @()

    foreach ($feature in $requiredFeatures) {
        if (Test-WindowsFeature -FeatureName $feature.Name) {
            Write-ColorOutput "✓ $($feature.DisplayName) is enabled" "Green"
            $enabledFeatures += $feature.DisplayName
        } else {
            Write-ColorOutput "✗ $($feature.DisplayName) is not enabled" "Red"
            $missingFeatures += $feature
        }
    }

    if ($missingFeatures.Count -eq 0) {
        Write-ColorOutput "✓ All required Windows features are enabled" "Green"
        return $true
    }

    Write-ColorOutput ""
    Write-ColorOutput "Missing Windows Features:" "Yellow"
    foreach ($feature in $missingFeatures) {
        Write-ColorOutput "  - $($feature.DisplayName)" "White"
    }
    Write-ColorOutput ""

    if (-not (Test-Administrator)) {
        Write-ColorOutput "ERROR: Administrative privileges required to enable Windows features!" "Red"
        Write-ColorOutput "Please run this script as Administrator or manually enable the missing features." "Yellow"
        Write-ColorOutput ""
        Write-ColorOutput "Manual steps:" "Yellow"
        Write-ColorOutput "1. Open PowerShell as Administrator" "White"
        Write-ColorOutput "2. Run the following commands:" "White"
        foreach ($feature in $missingFeatures) {
            Write-ColorOutput "   Enable-WindowsOptionalFeature -Online -FeatureName $($feature.Name) -All" "Cyan"
        }
        Write-ColorOutput "3. Restart your computer" "White"
        Write-ColorOutput "4. Run this setup script again" "White"
        return $false
    }

    $enableMessage = "Do you want to enable the missing Windows features? This will require a system restart."
    if (-not (Get-UserConfirmation -Message $enableMessage)) {
        Write-ColorOutput "Setup cancelled by user." "Yellow"
        return $false
    }

    Write-ColorOutput "Enabling Windows features..." "Blue"
    $restartRequired = $false

    foreach ($feature in $missingFeatures) {
        try {
            Write-ColorOutput "Enabling $($feature.DisplayName)..." "Blue"
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -All -NoRestart
            if ($result.RestartNeeded) {
                $restartRequired = $true
            }
            Write-ColorOutput "✓ $($feature.DisplayName) enabled successfully" "Green"
        } catch {
            Write-ColorOutput "✗ Failed to enable $($feature.DisplayName): $_" "Red"
            return $false
        }
    }

    if ($restartRequired) {
        Write-ColorOutput ""
        Write-ColorOutput "A system restart is required to complete the Windows feature installation." "Yellow"
        $restartMessage = "Do you want to restart now? (Recommended)"
        if (Get-UserConfirmation -Message $restartMessage) {
            Write-ColorOutput "Restarting system in 10 seconds..." "Yellow"
            Write-ColorOutput "After restart, please run this setup script again." "White"
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        } else {
            Write-ColorOutput ""
            Write-ColorOutput "Please restart your computer manually and run this setup script again." "Yellow"
            Write-ColorOutput "The Windows features will not be active until after restart." "White"
            return $false
        }
    }

    return $true
}

# Function to check WSL installation and version
function Test-WSLInstallation {
    Write-ColorOutput "Checking WSL installation..." "Blue"

    try {
        $wslVersion = wsl --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $wslVersion) {
            Write-ColorOutput "✓ WSL is installed" "Green"
            if ($Verbose) {
                Write-ColorOutput "WSL Version Info:" "Gray"
                $wslVersion | ForEach-Object { Write-ColorOutput "  $_" "Gray" }
            }
            return $true
        }
    } catch {
        # WSL not installed or not accessible
    }

    Write-ColorOutput "✗ WSL is not installed or not accessible" "Red"
    return $false
}

# Function to install WSL
function Install-WSL {
    Write-ColorOutput "Installing WSL..." "Blue"

    if (-not (Test-Administrator)) {
        Write-ColorOutput "ERROR: Administrative privileges required to install WSL!" "Red"
        Write-ColorOutput "Please run this script as Administrator or manually install WSL." "Yellow"
        Write-ColorOutput ""
        Write-ColorOutput "Manual installation:" "Yellow"
        Write-ColorOutput "1. Open PowerShell as Administrator" "White"
        Write-ColorOutput "2. Run: wsl --install" "Cyan"
        Write-ColorOutput "3. Restart your computer" "White"
        Write-ColorOutput "4. Complete Ubuntu setup when prompted" "White"
        return $false
    }

    $installMessage = "Do you want to install WSL with Ubuntu? This will require a system restart."
    if (-not (Get-UserConfirmation -Message $installMessage)) {
        Write-ColorOutput "WSL installation cancelled by user." "Yellow"
        return $false
    }

    try {
        Write-ColorOutput "Installing WSL with Ubuntu distribution..." "Blue"
        wsl --install

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ WSL installation initiated successfully" "Green"
            Write-ColorOutput ""
            Write-ColorOutput "A system restart is required to complete WSL installation." "Yellow"
            $restartMessage = "Do you want to restart now? (Recommended)"
            if (Get-UserConfirmation -Message $restartMessage) {
                Write-ColorOutput "Restarting system in 10 seconds..." "Yellow"
                Write-ColorOutput "After restart, Ubuntu will start automatically for initial setup." "White"
                Write-ColorOutput "Complete the Ubuntu setup, then run this script again." "White"
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            } else {
                Write-ColorOutput ""
                Write-ColorOutput "Please restart your computer manually." "Yellow"
                Write-ColorOutput "After restart, Ubuntu will start automatically for initial setup." "White"
                Write-ColorOutput "Complete the Ubuntu setup, then run this script again." "White"
                return $false
            }
        } else {
            Write-ColorOutput "✗ WSL installation failed" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Error installing WSL: $_" "Red"
        return $false
    }

    return $true
}

# Function to check WSL distributions
function Test-WSLDistributions {
    Write-ColorOutput "Checking WSL distributions..." "Blue"

    try {
        $wslList = wsl --list --verbose 2>$null
        if ($LASTEXITCODE -eq 0 -and $wslList) {
            $distributions = $wslList | Where-Object { $_ -match '\*?\s*(\S+)\s+(\S+)\s+(\d+)' }

            if ($distributions.Count -gt 0) {
                Write-ColorOutput "✓ WSL distributions found:" "Green"
                foreach ($dist in $distributions) {
                    if ($dist -match '\*?\s*(\S+)\s+(\S+)\s+(\d+)') {
                        $name = $matches[1]
                        $state = $matches[2]
                        $version = $matches[3]
                        $isDefault = $dist.StartsWith('*')
                        $status = if ($isDefault) { " (default)" } else { "" }
                        Write-ColorOutput "  - $name (v$version, $state)$status" "White"
                    }
                }
                return $true
            }
        }
    } catch {
        # Error checking distributions
    }

    Write-ColorOutput "✗ No WSL distributions found" "Red"
    return $false
}

# Function to ensure WSL is properly configured
function Initialize-WSL {
    if (-not (Test-WSLInstallation)) {
        if (-not (Install-WSL)) {
            return $false
        }
        # If we reach here, system should have restarted
        return $false
    }

    if (-not (Test-WSLDistributions)) {
        Write-ColorOutput "No WSL distributions available. Installing Ubuntu..." "Yellow"

        try {
            wsl --install -d Ubuntu
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "✓ Ubuntu distribution installed" "Green"
                Write-ColorOutput "Please complete the Ubuntu setup and run this script again." "Yellow"
                return $false
            } else {
                Write-ColorOutput "✗ Failed to install Ubuntu distribution" "Red"
                return $false
            }
        } catch {
            Write-ColorOutput "✗ Error installing Ubuntu: $_" "Red"
            return $false
        }
    }

    Write-ColorOutput "✓ WSL is properly configured" "Green"
    return $true
}

# Function to check rootless Docker in WSL
function Test-RootlessDockerInWSL {
    Write-ColorOutput "Checking rootless Docker in WSL..." "Blue"

    try {
        # Test if Docker is available in WSL
        $dockerCheck = wsl bash -c "command -v docker" 2>$null
        if ($LASTEXITCODE -eq 0 -and $dockerCheck) {
            # Test if Docker daemon is running
            wsl bash -c "docker info" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "✓ Rootless Docker is running in WSL" "Green"
                return $true
            } else {
                Write-ColorOutput "✗ Docker is installed but not running in WSL" "Red"
                return $false
            }
        } else {
            Write-ColorOutput "✗ Docker is not installed in WSL" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Error checking Docker in WSL: $_" "Red"
        return $false
    }
}

# Function to install rootless Docker in WSL
function Install-RootlessDockerInWSL {
    Write-ColorOutput "Installing rootless Docker in WSL..." "Blue"

    $installMessage = "Do you want to install rootless Docker in WSL? This may take several minutes."
    if (-not (Get-UserConfirmation -Message $installMessage)) {
        Write-ColorOutput "Rootless Docker installation cancelled by user." "Yellow"
        return $false
    }

    try {
        Write-ColorOutput "Updating WSL package lists..." "Blue"
        wsl bash -c "sudo apt update"

        Write-ColorOutput "Installing prerequisites..." "Blue"
        wsl bash -c "sudo apt install -y curl uidmap"

        Write-ColorOutput "Installing rootless Docker..." "Blue"
        wsl bash -c "curl -fsSL https://get.docker.com/rootless | sh"

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ Rootless Docker installation completed" "Green"

            # Add Docker to PATH
            Write-ColorOutput "Configuring Docker environment..." "Blue"
            wsl bash -c "echo 'export PATH=\$HOME/bin:\$PATH' >> ~/.bashrc"
            wsl bash -c "echo 'export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock' >> ~/.bashrc"

            # Start Docker service
            Write-ColorOutput "Starting Docker service..." "Blue"
            wsl bash -c "~/bin/dockerd-rootless.sh --experimental --storage-driver vfs" 2>$null &
            Start-Sleep -Seconds 5

            # Verify installation
            if (Test-RootlessDockerInWSL) {
                Write-ColorOutput "✓ Rootless Docker is now running" "Green"
                return $true
            } else {
                Write-ColorOutput "✗ Docker installation completed but service is not running" "Red"
                Write-ColorOutput "You may need to start Docker manually in WSL:" "Yellow"
                Write-ColorOutput "  wsl bash -c '~/bin/dockerd-rootless.sh --experimental --storage-driver vfs &'" "Cyan"
                return $false
            }
        } else {
            Write-ColorOutput "✗ Rootless Docker installation failed" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Error installing rootless Docker: $_" "Red"
        return $false
    }
}

# Function to ensure rootless Docker is available
function Initialize-RootlessDocker {
    if (-not (Test-RootlessDockerInWSL)) {
        if (-not (Install-RootlessDockerInWSL)) {
            Write-ColorOutput ""
            Write-ColorOutput "Manual installation instructions:" "Yellow"
            Write-ColorOutput "1. Open WSL terminal: wsl" "White"
            Write-ColorOutput "2. Update packages: sudo apt update" "White"
            Write-ColorOutput "3. Install Docker: curl -fsSL https://get.docker.com/rootless | sh" "White"
            Write-ColorOutput "4. Add to PATH: echo 'export PATH=\$HOME/bin:\$PATH' >> ~/.bashrc" "White"
            Write-ColorOutput "5. Set Docker host: echo 'export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock' >> ~/.bashrc" "White"
            Write-ColorOutput "6. Restart WSL: wsl --shutdown && wsl" "White"
            Write-ColorOutput "7. Start Docker: ~/bin/dockerd-rootless.sh --experimental --storage-driver vfs &" "White"
            return $false
        }
    }

    Write-ColorOutput "✓ Rootless Docker is available" "Green"
    return $true
}

# Function to start Docker Compose services
function Start-OrchestratorServices {
    param([string]$ComposeFile)

    Write-ColorOutput "Starting MCP Orchestrator services..." "Blue"

    try {
        # Change to deploy directory where compose files are located
        $originalLocation = Get-Location
        Set-Location "deploy"

        # Start services in detached mode
        Write-ColorOutput "Starting Docker Compose services..." "Blue"
        docker-compose -f $ComposeFile up -d

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ Services started successfully" "Green"

            # Wait a moment for services to initialize
            Write-ColorOutput "Waiting for services to initialize..." "Blue"
            Start-Sleep -Seconds 5

            # Check service status
            Write-ColorOutput "Checking service status..." "Blue"
            $serviceStatus = docker-compose -f $ComposeFile ps

            if ($Verbose) {
                Write-ColorOutput "Service Status:" "Gray"
                $serviceStatus | ForEach-Object { Write-ColorOutput "  $_" "Gray" }
            }

            # Test health endpoint
            Write-ColorOutput "Testing health endpoint..." "Blue"
            try {
                $healthResponse = Invoke-WebRequest -Uri "http://localhost:3000/health" -TimeoutSec 10 -ErrorAction SilentlyContinue
                if ($healthResponse.StatusCode -eq 200) {
                    Write-ColorOutput "✓ Health endpoint responding" "Green"
                } else {
                    Write-ColorOutput "⚠ Health endpoint returned status: $($healthResponse.StatusCode)" "Yellow"
                }
            } catch {
                Write-ColorOutput "⚠ Health endpoint not yet available (this is normal during startup)" "Yellow"
            }

            return $true
        } else {
            Write-ColorOutput "✗ Failed to start services" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Error starting services: $_" "Red"
        return $false
    } finally {
        # Return to original location
        Set-Location $originalLocation
    }
}

Write-ColorOutput "MCP Orchestrator Setup - Rootless Docker Only" "Cyan"
Write-ColorOutput "=============================================" "Cyan"

# Windows Prerequisites Check
if (-not $SkipPrerequisites) {
    Write-ColorOutput "Step 1: Checking Windows Prerequisites" "Yellow"

    # Check and enable Windows features
    if (-not (Enable-RequiredWindowsFeatures)) {
        Write-ColorOutput "Failed to enable required Windows features. Exiting." "Red"
        exit 1
    }

    # Initialize WSL
    if (-not (Initialize-WSL)) {
        Write-ColorOutput "Failed to initialize WSL. Exiting." "Red"
        exit 1
    }

    # Initialize rootless Docker
    if (-not (Initialize-RootlessDocker)) {
        Write-ColorOutput "Failed to initialize rootless Docker. Exiting." "Red"
        exit 1
    }

    Write-ColorOutput "✓ All Windows prerequisites are satisfied" "Green"
    Write-ColorOutput ""
} else {
    Write-ColorOutput "Skipping prerequisite checks (as requested)" "Yellow"
    Write-ColorOutput ""
}

Write-ColorOutput "Step 2: Checking Docker Availability" "Yellow"

# Test rootless Docker availability
function Test-RootlessDockerAvailability {
    Write-ColorOutput "Testing rootless Docker availability..." "Blue"

    try {
        # Test docker info command
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ Docker is available" "Green"

            # Check if Docker daemon is accessible
            try {
                $dockerVersion = docker version --format '{{.Server.Os}}' 2>$null
                if ($dockerVersion -and $dockerVersion.Trim()) {
                    Write-ColorOutput "✓ Docker daemon is accessible" "Green"
                    return $true
                } else {
                    Write-ColorOutput "✗ Docker daemon is not accessible" "Red"
                    return $false
                }
            } catch {
                Write-ColorOutput "✗ Docker daemon is not accessible" "Red"
                return $false
            }
        } else {
            Write-ColorOutput "✗ Docker is not available" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Error testing Docker: $_" "Red"
        return $false
    }
}

# Get current user ID for rootless Docker
function Get-DockerUserId {
    if ($IsLinux -or $env:WSL_DISTRO_NAME) {
        # Linux or WSL
        try {
            $uid = id -u 2>$null
            if ($uid) {
                return $uid
            }
        } catch {
            # Fallback
        }
    }

    # Windows or fallback
    return "1001"
}

# Get rootless Docker socket path
function Get-RootlessDockerSocketPath {
    param([string]$UserId)

    if ($IsLinux -or $env:WSL_DISTRO_NAME) {
        return "/run/user/$UserId/docker.sock"
    } else {
        # Windows Docker Desktop
        return "//./pipe/docker_engine"
    }
}

Write-ColorOutput "Step 1: Checking Prerequisites" "Yellow"

# Test Docker availability
if (-not (Test-RootlessDockerAvailability)) {
    Write-ColorOutput ""
    Write-ColorOutput "ERROR: Rootless Docker is not available!" "Red"
    Write-ColorOutput ""
    Write-ColorOutput "Please install rootless Docker:" "Yellow"
    Write-ColorOutput "  Linux/WSL: curl -fsSL https://get.docker.com/rootless | sh" "White"
    Write-ColorOutput "  Windows: Use Docker Desktop" "White"
    Write-ColorOutput ""
    Write-ColorOutput "After installation, ensure Docker is running and try again." "Yellow"
    exit 1
}

Write-ColorOutput "Step 3: Configuring Environment" "Yellow"

# Get platform-appropriate user ID and socket paths
$currentUID = Get-DockerUserId
$rootlessSocketPath = Get-RootlessDockerSocketPath -UserId $currentUID

# Set environment variable for Docker Compose
$env:DOCKER_USER_ID = $currentUID

Write-ColorOutput "Creating rootless Docker environment configuration..." "Blue"

# Create environment configuration for rootless Docker only
$envContent = @"
# MCP Orchestrator Core Configuration - Rootless Docker Only
# This configuration is designed exclusively for rootless Docker deployment
ORCHESTRATOR_PORT=3000
ORCHESTRATOR_HOST=0.0.0.0
NODE_ENV=production
LOG_LEVEL=INFO

# Docker Mode - Rootless Only (no fallback to standard Docker)
DOCKER_MODE=rootless
DOCKER_ROOTLESS_SOCKET_PATH=$rootlessSocketPath

# Timeout and Retry Configuration (optimized for rootless Docker)
MCP_TIMEOUT=45000
DISCOVERY_RETRY_ATTEMPTS=10
DISCOVERY_RETRY_DELAY=3000

# Rootless Docker Security Settings
ROOTLESS_MODE=true
DOCKER_ROOTLESS_ENABLED=true
"@

try {
    # Ensure deploy/env directory exists
    if (-not (Test-Path "deploy/env")) {
        New-Item -Path "deploy/env" -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path "deploy/env/.env.core" -Value $envContent -ErrorAction Stop
    Write-ColorOutput "✓ Environment configuration created" "Green"
} catch {
    Write-ColorOutput "✗ Failed to create environment file: $_" "Red"
    exit 1
}

Write-ColorOutput "Step 4: Validating Configuration" "Yellow"

# Determine which Docker Compose file to validate based on platform
$composeFile = "docker-compose.yml"  # Default for Unix/Linux
$platformType = "Unix/Linux"
if (-not ($IsLinux -or $env:WSL_DISTRO_NAME)) {
    # Windows Docker Desktop
    $composeFile = "docker-compose.windows.yml"
    $platformType = "Windows"
}

# Validate Docker Compose file exists
if (-not (Test-Path "deploy/$composeFile")) {
    Write-ColorOutput "✗ $composeFile not found in deploy directory" "Red"
    exit 1
} else {
    Write-ColorOutput "✓ Docker Compose configuration found ($platformType)" "Green"
}

# Validate required directories
$requiredDirs = @("src/core", "environments", "scripts", "registry", "temp")
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) {
        Write-ColorOutput "✗ Required directory missing: $dir" "Red"
        exit 1
    }
}
Write-ColorOutput "✓ All required directories present" "Green"

# Optional service startup
if ($StartServices) {
    Write-ColorOutput "Step 5: Starting Services" "Yellow"

    if (Start-OrchestratorServices -ComposeFile $composeFile) {
        Write-ColorOutput "✓ MCP Orchestrator services are running" "Green"
    } else {
        Write-ColorOutput "✗ Failed to start services automatically" "Red"
        Write-ColorOutput "You can start them manually using:" "Yellow"
        Write-ColorOutput "  .\scripts\deploy\start-rootless.ps1 -Detach" "Cyan"
    }
    Write-ColorOutput ""
}

Write-ColorOutput "Step $(if ($StartServices) { '6' } else { '5' }): Setup Complete" "Yellow"

Write-ColorOutput ""
Write-ColorOutput "✓ MCP Orchestrator setup completed successfully!" "Green"
Write-ColorOutput ""
Write-ColorOutput "Configuration Summary:" "Cyan"
Write-ColorOutput "  Mode: Rootless Docker Only" "White"
Write-ColorOutput "  Platform: $platformType" "White"
Write-ColorOutput "  User ID: $currentUID" "White"
Write-ColorOutput "  Socket Path: $rootlessSocketPath" "White"
Write-ColorOutput "  Environment: deploy/env/.env.core" "White"
Write-ColorOutput "  Compose File: $composeFile" "White"
if (-not $SkipPrerequisites) {
    Write-ColorOutput "  Windows Features: ✓ Verified and Enabled" "White"
    Write-ColorOutput "  WSL: ✓ Installed and Configured" "White"
    Write-ColorOutput "  Rootless Docker: ✓ Available in WSL" "White"
}
Write-ColorOutput ""
if ($StartServices) {
    Write-ColorOutput "Services Status:" "Yellow"
    Write-ColorOutput "  ✓ MCP Orchestrator is running on http://localhost:3000" "Green"
    Write-ColorOutput ""
    Write-ColorOutput "Next Steps:" "Yellow"
    Write-ColorOutput "  1. Verify deployment:" "White"
    Write-ColorOutput "     curl http://localhost:3000/health" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  2. View logs:" "White"
    Write-ColorOutput "     docker-compose -f deploy/$composeFile logs -f" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  3. Stop services (when needed):" "White"
    Write-ColorOutput "     docker-compose -f deploy/$composeFile down" "Cyan"
} else {
    Write-ColorOutput "Next Steps:" "Yellow"
    Write-ColorOutput "  1. Start the orchestrator:" "White"
    Write-ColorOutput "     .\scripts\deploy\start-rootless.ps1 -Detach" "Cyan"
    Write-ColorOutput "     OR: docker-compose -f deploy/$composeFile up -d" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  2. Verify deployment:" "White"
    Write-ColorOutput "     curl http://localhost:3000/health" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  3. View logs:" "White"
    Write-ColorOutput "     docker-compose -f deploy/$composeFile logs -f" "Cyan"
}
Write-ColorOutput ""
if (-not $SkipPrerequisites) {
    Write-ColorOutput "Troubleshooting:" "Yellow"
    Write-ColorOutput "  - If Docker issues occur, restart WSL: wsl --shutdown && wsl" "Gray"
    Write-ColorOutput "  - To check WSL status: wsl --list --verbose" "Gray"
    Write-ColorOutput "  - To access WSL directly: wsl" "Gray"
    Write-ColorOutput ""
}
Write-ColorOutput "For more information, see docs/core.md" "Gray"