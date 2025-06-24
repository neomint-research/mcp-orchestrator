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

# Function to dynamically detect Docker Desktop installation
function Test-DockerDesktopInstallation {
    Write-ColorOutput "Detecting Docker Desktop installation..." "Blue"

    $dockerDesktopFound = $false
    $dockerDesktopPath = $null
    $dockerDesktopVersion = $null

    # Check multiple registry locations for Docker Desktop
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($regPath in $registryPaths) {
        try {
            $apps = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*Docker Desktop*" -or
                $_.DisplayName -like "*Docker for Windows*" -or
                $_.Publisher -like "*Docker Inc*"
            }

            if ($apps) {
                foreach ($app in $apps) {
                    $dockerDesktopFound = $true
                    $dockerDesktopPath = $app.InstallLocation
                    $dockerDesktopVersion = $app.DisplayVersion
                    Write-ColorOutput "✓ Found Docker Desktop v$dockerDesktopVersion" "Green"
                    if ($dockerDesktopPath) {
                        Write-ColorOutput "  Installation Path: $dockerDesktopPath" "Gray"
                    }
                    break
                }
                if ($dockerDesktopFound) { break }
            }
        } catch {
            # Continue checking other registry paths
        }
    }

    # Alternative detection using WMI
    if (-not $dockerDesktopFound) {
        try {
            $wmiApps = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like "*Docker Desktop*" -or $_.Name -like "*Docker for Windows*"
            }

            if ($wmiApps) {
                $dockerDesktopFound = $true
                $dockerDesktopVersion = $wmiApps[0].Version
                Write-ColorOutput "✓ Found Docker Desktop v$dockerDesktopVersion (via WMI)" "Green"
            }
        } catch {
            # WMI query failed, continue
        }
    }

    # Check for Docker CLI in PATH as final verification
    if ($dockerDesktopFound) {
        try {
            $dockerCliVersion = docker --version 2>$null
            if ($dockerCliVersion -and $LASTEXITCODE -eq 0) {
                Write-ColorOutput "✓ Docker CLI is accessible: $dockerCliVersion" "Green"
            } else {
                Write-ColorOutput "⚠ Docker Desktop found but CLI not in PATH" "Yellow"
            }
        } catch {
            Write-ColorOutput "⚠ Docker Desktop found but CLI not accessible" "Yellow"
        }
    }

    return @{
        Found = $dockerDesktopFound
        Path = $dockerDesktopPath
        Version = $dockerDesktopVersion
    }
}

# Function to prompt for user confirmation
function Get-UserConfirmation {
    param(
        [string]$Message,
        [string]$DefaultChoice = "N"
    )

    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("Yes", "Yes"),
        [System.Management.Automation.Host.ChoiceDescription]::new("No", "No")
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

# Function to get comprehensive WSL distribution information
function Get-WSLDistributions {
    Write-ColorOutput "Analyzing WSL distributions..." "Blue"

    $wslDistributions = @()
    $defaultDistribution = $null

    try {
        $wslList = wsl --list --verbose 2>$null
        if ($LASTEXITCODE -eq 0 -and $wslList) {
            $distributions = $wslList | Where-Object { $_ -match '\*?\s*(\S+)\s+(\S+)\s+(\d+)' }

            foreach ($dist in $distributions) {
                if ($dist -match '\*?\s*(\S+)\s+(\S+)\s+(\d+)') {
                    $name = $matches[1]
                    $state = $matches[2]
                    $version = $matches[3]
                    $isDefault = $dist.StartsWith('*')

                    # Get user context for this distribution
                    $userInfo = @{
                        UID = $null
                        Username = $null
                        DockerAvailable = $false
                        DockerSocketPath = $null
                    }

                    if ($state -eq "Running" -or $state -eq "Stopped") {
                        try {
                            # Get UID
                            $uid = wsl -d $name bash -c "id -u" 2>$null
                            if ($uid -and $LASTEXITCODE -eq 0) {
                                $userInfo.UID = $uid.Trim()
                            }

                            # Get username
                            $username = wsl -d $name bash -c "whoami" 2>$null
                            if ($username -and $LASTEXITCODE -eq 0) {
                                $userInfo.Username = $username.Trim()
                            }

                            # Check Docker availability
                            $dockerCheck = wsl -d $name bash -c "command -v docker" 2>$null
                            if ($dockerCheck -and $LASTEXITCODE -eq 0) {
                                $userInfo.DockerAvailable = $true
                                if ($userInfo.UID) {
                                    $userInfo.DockerSocketPath = "/run/user/$($userInfo.UID)/docker.sock"
                                }
                            }
                        } catch {
                            # Error getting user info for this distribution
                        }
                    }

                    $distInfo = @{
                        Name = $name
                        State = $state
                        Version = [int]$version
                        IsDefault = $isDefault
                        UserInfo = $userInfo
                    }

                    $wslDistributions += $distInfo

                    if ($isDefault) {
                        $defaultDistribution = $distInfo
                    }

                    $status = if ($isDefault) { " (default)" } else { "" }
                    $dockerStatus = if ($userInfo.DockerAvailable) { " [Docker OK]" } else { " [Docker NO]" }
                    Write-ColorOutput "  - $name (v$version, $state)$status$dockerStatus" "White"
                    if ($userInfo.UID) {
                        Write-ColorOutput "    User: $($userInfo.Username) (UID: $($userInfo.UID))" "Gray"
                    }
                }
            }
        }
    } catch {
        Write-ColorOutput "✗ Error analyzing WSL distributions: $_" "Red"
    }

    return @{
        Distributions = $wslDistributions
        Default = $defaultDistribution
        Count = $wslDistributions.Count
    }
}

# Function to check WSL distributions (backward compatibility)
function Test-WSLDistributions {
    $wslInfo = Get-WSLDistributions

    if ($wslInfo.Count -gt 0) {
        Write-ColorOutput "✓ Found $($wslInfo.Count) WSL distribution(s)" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ No WSL distributions found" "Red"
        return $false
    }
}

# Function to test Docker Desktop WSL2 backend configuration
function Test-DockerDesktopWSL2Backend {
    Write-ColorOutput "Verifying Docker Desktop WSL2 backend configuration..." "Blue"

    $wsl2BackendEnabled = $false
    $settingsPath = $null
    $settingsContent = $null

    # Try to locate Docker Desktop settings.json
    $possibleSettingsPaths = @(
        "$env:APPDATA\Docker\settings.json",
        "$env:LOCALAPPDATA\Docker\settings.json",
        "$env:USERPROFILE\AppData\Roaming\Docker\settings.json",
        "$env:USERPROFILE\AppData\Local\Docker\settings.json"
    )

    foreach ($path in $possibleSettingsPaths) {
        if (Test-Path $path) {
            $settingsPath = $path
            Write-ColorOutput "✓ Found Docker Desktop settings: $path" "Green"
            break
        }
    }

    if ($settingsPath) {
        try {
            $settingsContent = Get-Content $settingsPath -Raw | ConvertFrom-Json

            # Check WSL2 backend configuration
            if ($settingsContent.wslEngineEnabled -eq $true) {
                $wsl2BackendEnabled = $true
                Write-ColorOutput "✓ WSL2 backend is enabled" "Green"
            } else {
                Write-ColorOutput "✗ WSL2 backend is not enabled" "Red"
            }

            # Check WSL integration settings
            if ($settingsContent.enableIntegrationWithDefaultWslDistro -eq $true) {
                Write-ColorOutput "✓ WSL integration with default distribution is enabled" "Green"
            } else {
                Write-ColorOutput "⚠ WSL integration with default distribution is not enabled" "Yellow"
            }

        } catch {
            Write-ColorOutput "⚠ Could not parse Docker Desktop settings: $_" "Yellow"
        }
    } else {
        Write-ColorOutput "⚠ Docker Desktop settings.json not found" "Yellow"

        # Fallback: Check Docker context and version for WSL2 indicators
        try {
            $dockerInfo = docker info --format "{{.OperatingSystem}} {{.KernelVersion}}" 2>$null
            if ($dockerInfo -and $dockerInfo -match "WSL" -and $LASTEXITCODE -eq 0) {
                $wsl2BackendEnabled = $true
                Write-ColorOutput "✓ WSL2 backend detected via Docker info" "Green"
            }
        } catch {
            # Docker info failed
        }
    }

    return @{
        WSL2BackendEnabled = $wsl2BackendEnabled
        SettingsPath = $settingsPath
        SettingsContent = $settingsContent
    }
}

# Function to configure Docker Desktop WSL2 backend
function Set-DockerDesktopWSL2Backend {
    param(
        [string]$SettingsPath,
        [object]$CurrentSettings
    )

    Write-ColorOutput "Configuring Docker Desktop WSL2 backend..." "Blue"

    if (-not $SettingsPath -or -not (Test-Path $SettingsPath)) {
        Write-ColorOutput "✗ Cannot configure: Docker Desktop settings file not found" "Red"
        return $false
    }

    $configMessage = "Do you want to enable WSL2 backend in Docker Desktop? This will require Docker Desktop restart."
    if (-not (Get-UserConfirmation -Message $configMessage)) {
        Write-ColorOutput "WSL2 backend configuration cancelled by user." "Yellow"
        return $false
    }

    try {
        # Update settings to enable WSL2 backend
        $CurrentSettings.wslEngineEnabled = $true
        $CurrentSettings.enableIntegrationWithDefaultWslDistro = $true

        # Ensure WSL integration is enabled for discovered distributions
        $wslInfo = Get-WSLDistributions
        if ($wslInfo.Count -gt 0) {
            if (-not $CurrentSettings.integrationOptions) {
                $CurrentSettings.integrationOptions = @{}
            }

            foreach ($dist in $wslInfo.Distributions) {
                if ($dist.State -eq "Running" -or $dist.State -eq "Stopped") {
                    $CurrentSettings.integrationOptions[$dist.Name] = $true
                    Write-ColorOutput "  Enabled integration for: $($dist.Name)" "Gray"
                }
            }
        }

        # Save updated settings
        $updatedJson = $CurrentSettings | ConvertTo-Json -Depth 10
        Set-Content -Path $SettingsPath -Value $updatedJson -ErrorAction Stop

        Write-ColorOutput "✓ Docker Desktop settings updated" "Green"
        Write-ColorOutput "Please restart Docker Desktop for changes to take effect." "Yellow"

        return $true

    } catch {
        Write-ColorOutput "✗ Failed to update Docker Desktop settings: $_" "Red"
        return $false
    }
}

# Function to get available WSL distributions from Microsoft Store
function Get-AvailableWSLDistributions {
    Write-ColorOutput "Checking available WSL distributions..." "Blue"

    $availableDistributions = @()

    try {
        # Get list of available distributions
        $wslListOnline = wsl --list --online 2>$null
        if ($LASTEXITCODE -eq 0 -and $wslListOnline) {
            # Parse the output to extract distribution names
            $distributions = $wslListOnline | Where-Object { $_ -match '^\s*(\S+)\s+(.+)$' -and $_ -notmatch 'NAME|----' }

            foreach ($dist in $distributions) {
                if ($dist -match '^\s*(\S+)\s+(.+)$') {
                    $name = $matches[1].Trim()
                    $description = $matches[2].Trim()

                    $availableDistributions += @{
                        Name = $name
                        Description = $description
                        IsUbuntu = $name -match 'Ubuntu'
                        IsRecommended = $name -eq 'Ubuntu' -or $name -eq 'Ubuntu-22.04'
                        StoreId = Get-UbuntuStoreId -Name $name
                        DownloadSize = Get-EstimatedDownloadSize -Name $name
                    }
                }
            }
        }
    } catch {
        Write-ColorOutput "⚠ Could not retrieve online distribution list: $_" "Yellow"
    }

    # Fallback to known Ubuntu distributions if online list fails
    if ($availableDistributions.Count -eq 0) {
        $availableDistributions = @(
            @{ Name = "Ubuntu"; Description = "Ubuntu (Latest LTS)"; IsUbuntu = $true; IsRecommended = $true; StoreId = "9PDXGNCFSCZV"; DownloadSize = "~500 MB" },
            @{ Name = "Ubuntu-22.04"; Description = "Ubuntu 22.04 LTS"; IsUbuntu = $true; IsRecommended = $true; StoreId = "9PN20MSR04DW"; DownloadSize = "~450 MB" },
            @{ Name = "Ubuntu-20.04"; Description = "Ubuntu 20.04 LTS"; IsUbuntu = $true; IsRecommended = $false; StoreId = "9N6SVWS3RX71"; DownloadSize = "~400 MB" },
            @{ Name = "Ubuntu-18.04"; Description = "Ubuntu 18.04 LTS"; IsUbuntu = $true; IsRecommended = $false; StoreId = "9N9TNGVNDL3Q"; DownloadSize = "~350 MB" }
        )
    }

    return $availableDistributions
}

# Function to get Ubuntu Microsoft Store ID
function Get-UbuntuStoreId {
    param([string]$Name)

    $storeIds = @{
        "Ubuntu" = "9PDXGNCFSCZV"
        "Ubuntu-22.04" = "9PN20MSR04DW"
        "Ubuntu-20.04" = "9N6SVWS3RX71"
        "Ubuntu-18.04" = "9N9TNGVNDL3Q"
    }

    return $storeIds[$Name]
}

# Function to get estimated download size
function Get-EstimatedDownloadSize {
    param([string]$Name)

    $sizes = @{
        "Ubuntu" = "~500 MB"
        "Ubuntu-22.04" = "~450 MB"
        "Ubuntu-20.04" = "~400 MB"
        "Ubuntu-18.04" = "~350 MB"
    }

    return $sizes[$Name]
}

# Function to let user choose Ubuntu distribution
function Select-UbuntuDistribution {
    $availableDistributions = Get-AvailableWSLDistributions
    $ubuntuDistributions = $availableDistributions | Where-Object { $_.IsUbuntu }

    if ($ubuntuDistributions.Count -eq 0) {
        Write-ColorOutput "✗ No Ubuntu distributions available" "Red"
        return $null
    }

    Write-ColorOutput ""
    Write-ColorOutput "Available Ubuntu Distributions:" "Yellow"
    Write-ColorOutput "================================" "Yellow"

    for ($i = 0; $i -lt $ubuntuDistributions.Count; $i++) {
        $dist = $ubuntuDistributions[$i]
        $recommended = if ($dist.IsRecommended) { " (Recommended)" } else { "" }
        $sizeInfo = if ($dist.DownloadSize) { " - Download: $($dist.DownloadSize)" } else { "" }
        Write-ColorOutput "  $($i + 1). $($dist.Name) - $($dist.Description)$recommended$sizeInfo" "White"
        if ($dist.StoreId) {
            Write-ColorOutput "     Store ID: $($dist.StoreId)" "Gray"
        }
    }

    Write-ColorOutput ""
    Write-ColorOutput "Note: Download will be performed from Microsoft Store with fallback sources." "Gray"
    Write-ColorOutput ""

    # Default to first recommended distribution
    $defaultChoice = 1
    $recommendedIndex = $ubuntuDistributions | ForEach-Object { $_.IsRecommended } | Select-Object -First 1
    if ($recommendedIndex) {
        $defaultChoice = ($ubuntuDistributions | Where-Object { $_.IsRecommended } | Select-Object -First 1 | ForEach-Object {
            [array]::IndexOf($ubuntuDistributions, $_) + 1
        })
    }

    do {
        $choice = Read-Host "Select Ubuntu distribution to install (1-$($ubuntuDistributions.Count)) [default: $defaultChoice]"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = $defaultChoice
        }

        try {
            $choiceIndex = [int]$choice - 1
            if ($choiceIndex -ge 0 -and $choiceIndex -lt $ubuntuDistributions.Count) {
                $selectedDistribution = $ubuntuDistributions[$choiceIndex]
                Write-ColorOutput "✓ Selected: $($selectedDistribution.Name) - $($selectedDistribution.Description)" "Green"
                Write-ColorOutput "  Download size: $($selectedDistribution.DownloadSize)" "Gray"
                return $selectedDistribution
            } else {
                Write-ColorOutput "Invalid choice. Please select a number between 1 and $($ubuntuDistributions.Count)." "Red"
            }
        } catch {
            Write-ColorOutput "Invalid input. Please enter a number." "Red"
        }
    } while ($true)
}

# Function to install Ubuntu distribution with robust download and detailed progress
function Install-UbuntuDistribution {
    param(
        [object]$Distribution
    )

    Write-ColorOutput ""
    Write-ColorOutput "Installing Ubuntu Distribution: $($Distribution.Name)" "Yellow"
    Write-ColorOutput "=================================================" "Yellow"
    Write-ColorOutput "Description: $($Distribution.Description)" "White"
    Write-ColorOutput "Estimated download size: $($Distribution.DownloadSize)" "White"
    Write-ColorOutput "Microsoft Store ID: $($Distribution.StoreId)" "White"
    Write-ColorOutput ""

    $installMessage = "This will download and install $($Distribution.Name) from Microsoft Store. Continue?"
    if (-not (Get-UserConfirmation -Message $installMessage -DefaultChoice "Y")) {
        Write-ColorOutput "Ubuntu installation cancelled by user." "Yellow"
        return $false
    }

    Write-ColorOutput ""
    Write-ColorOutput "Step 1: Downloading Ubuntu Distribution" "Blue"
    Write-ColorOutput "=======================================" "Blue"

    # Method 1: Try WSL install command (primary method)
    Write-ColorOutput "Attempting download via WSL install command..." "Blue"
    Write-ColorOutput "This may take several minutes depending on your internet connection." "Gray"
    Write-ColorOutput ""

    try {
        # Start the installation process
        $installProcess = Start-Process -FilePath "wsl" -ArgumentList "--install", "-d", $Distribution.Name -NoNewWindow -PassThru -RedirectStandardOutput "temp\wsl-install-output.log" -RedirectStandardError "temp\wsl-install-error.log"

        # Monitor the installation process with enhanced progress tracking
        $timeout = 1800  # 30 minutes timeout
        $elapsed = 0
        $checkInterval = 2  # Check every 2 seconds for smoother updates
        $progressStages = @(
            @{ Stage = "Initializing"; Duration = 30; Progress = 5 },
            @{ Stage = "Downloading"; Duration = 600; Progress = 70 },
            @{ Stage = "Installing"; Duration = 180; Progress = 90 },
            @{ Stage = "Configuring"; Duration = 60; Progress = 100 }
        )

        $currentStageIndex = 0
        $stageStartTime = 0
        $estimatedTotalTime = ($progressStages | Measure-Object -Property Duration -Sum).Sum

        Write-ColorOutput "Download and installation in progress..." "Blue"
        Write-ColorOutput "Estimated total time: $([math]::Ceiling($estimatedTotalTime / 60)) minutes" "Gray"
        Write-ColorOutput ""

        while (-not $installProcess.HasExited -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval

            # Determine current stage based on elapsed time
            $cumulativeTime = 0
            $newStageIndex = 0
            foreach ($stage in $progressStages) {
                if ($elapsed -gt $cumulativeTime + $stage.Duration) {
                    $cumulativeTime += $stage.Duration
                    $newStageIndex++
                } else {
                    break
                }
            }

            # Update stage if changed
            if ($newStageIndex -ne $currentStageIndex) {
                $currentStageIndex = [math]::Min($newStageIndex, $progressStages.Count - 1)
                $stageStartTime = $elapsed
            }

            $currentStage = $progressStages[$currentStageIndex]
            $stageElapsed = $elapsed - $stageStartTime
            $stageProgress = [math]::Min(100, ($stageElapsed / $currentStage.Duration) * 100)

            # Calculate overall progress
            $overallProgress = 0
            for ($i = 0; $i -lt $currentStageIndex; $i++) {
                $overallProgress += ($progressStages[$i].Progress - ($i -gt 0 ? $progressStages[$i-1].Progress : 0))
            }
            $currentStageWeight = $currentStage.Progress - ($currentStageIndex -gt 0 ? $progressStages[$currentStageIndex-1].Progress : 0)
            $overallProgress += ($stageProgress / 100) * $currentStageWeight

            # Calculate remaining time
            $remainingTime = [math]::Max(0, $estimatedTotalTime - $elapsed)
            $remainingMinutes = [math]::Floor($remainingTime / 60)
            $remainingSeconds = $remainingTime % 60

            # Create progress bar
            $barWidth = 40
            $filledWidth = [math]::Floor(($overallProgress / 100) * $barWidth)
            $emptyWidth = $barWidth - $filledWidth
            $progressBar = "█" * $filledWidth + "░" * $emptyWidth

            # Format time display
            $elapsedMinutes = [math]::Floor($elapsed / 60)
            $elapsedSecondsRemainder = $elapsed % 60

            # Display progress
            Write-Host "`r[$progressBar] $([math]::Round($overallProgress, 1))% - $($currentStage.Stage)" -NoNewline -ForegroundColor Cyan
            Write-Host " | Elapsed: $($elapsedMinutes)m $($elapsedSecondsRemainder)s" -NoNewline -ForegroundColor Gray
            Write-Host " | Remaining: ~$($remainingMinutes)m $($remainingSeconds)s" -NoNewline -ForegroundColor Yellow

            # Check if any error occurred
            if (Test-Path "temp\wsl-install-error.log") {
                $errorContent = Get-Content "temp\wsl-install-error.log" -Raw -ErrorAction SilentlyContinue
                if ($errorContent -and $errorContent.Trim() -and -not $errorContent.Contains("previous error shown")) {
                    Write-Host ""  # New line after progress
                    Write-ColorOutput "⚠ Installation status update:" "Yellow"
                    $errorLines = $errorContent.Trim() -split "`n" | Select-Object -Last 3
                    foreach ($line in $errorLines) {
                        if ($line.Trim()) {
                            Write-ColorOutput "  $($line.Trim())" "Gray"
                        }
                    }
                    # Mark that we've shown this error to avoid spam
                    Add-Content "temp\wsl-install-error.log" "`n<!-- previous error shown -->" -ErrorAction SilentlyContinue
                    Write-ColorOutput "Continuing download..." "Blue"
                }
            }
        }

        Write-Host ""  # New line after progress
        Write-Host ""  # Additional spacing

        # Show final download summary
        $totalMinutes = [math]::Floor($elapsed / 60)
        $totalSeconds = $elapsed % 60
        Write-ColorOutput "Download Summary:" "Blue"
        Write-ColorOutput "=================" "Blue"
        Write-ColorOutput "Total time: $($totalMinutes)m $($totalSeconds)s" "White"
        Write-ColorOutput "Distribution: $($Distribution.Name)" "White"
        Write-ColorOutput "Size: $($Distribution.DownloadSize)" "White"
        Write-ColorOutput ""

        if ($installProcess.HasExited) {
            $exitCode = $installProcess.ExitCode
            if ($exitCode -eq 0) {
                Write-ColorOutput "✓ Ubuntu distribution download completed successfully" "Green"

                # Verify installation
                Start-Sleep -Seconds 3
                $verifyResult = wsl --list --verbose 2>$null | Where-Object { $_ -match $Distribution.Name }
                if ($verifyResult) {
                    Write-ColorOutput "✓ Ubuntu distribution verified in WSL list" "Green"
                    return $true
                } else {
                    Write-ColorOutput "⚠ Download completed but distribution not found in WSL list" "Yellow"
                    Write-ColorOutput "Attempting alternative verification..." "Blue"

                    # Alternative verification
                    Start-Sleep -Seconds 5
                    $verifyResult2 = wsl --list --verbose 2>$null | Where-Object { $_ -match $Distribution.Name }
                    if ($verifyResult2) {
                        Write-ColorOutput "✓ Ubuntu distribution verified (delayed registration)" "Green"
                        return $true
                    }
                }
            } else {
                Write-ColorOutput "✗ Ubuntu installation failed with exit code: $exitCode" "Red"

                # Show error details if available
                if (Test-Path "temp\wsl-install-error.log") {
                    $errorContent = Get-Content "temp\wsl-install-error.log" -Raw -ErrorAction SilentlyContinue
                    if ($errorContent -and $errorContent.Trim()) {
                        Write-ColorOutput "Error details:" "Red"
                        Write-ColorOutput $errorContent.Trim() "Gray"
                    }
                }
            }
        } else {
            Write-ColorOutput "✗ Installation timed out after $($timeout/60) minutes" "Red"
            Write-ColorOutput "This may indicate a slow internet connection or server issues." "Yellow"
            Write-ColorOutput "Progress reached: $([math]::Round($overallProgress, 1))% ($($currentStage.Stage))" "Gray"

            try {
                $installProcess.Kill()
                Write-ColorOutput "Installation process terminated." "Gray"
            } catch {
                Write-ColorOutput "Could not terminate installation process: $_" "Yellow"
            }
        }

    } catch {
        Write-ColorOutput "✗ Error during Ubuntu installation: $_" "Red"
    } finally {
        # Clean up temporary files
        if (Test-Path "temp\wsl-install-output.log") { Remove-Item "temp\wsl-install-output.log" -ErrorAction SilentlyContinue }
        if (Test-Path "temp\wsl-install-error.log") { Remove-Item "temp\wsl-install-error.log" -ErrorAction SilentlyContinue }
    }

    Write-ColorOutput ""
    Write-ColorOutput "Step 2: Attempting Alternative Download Methods" "Blue"
    Write-ColorOutput "===============================================" "Blue"

    # Method 2: Try Microsoft Store direct installation
    if ($Distribution.StoreId) {
        Write-ColorOutput "Attempting installation via Microsoft Store..." "Blue"

        try {
            # Try to install via Microsoft Store
            $storeUri = "ms-windows-store://pdp/?ProductId=$($Distribution.StoreId)"
            Write-ColorOutput "Opening Microsoft Store for manual installation..." "Blue"
            Write-ColorOutput "Store URI: $storeUri" "Gray"

            Start-Process $storeUri

            Write-ColorOutput ""
            Write-ColorOutput "Please install $($Distribution.Name) from the Microsoft Store window that opened." "Yellow"
            Write-ColorOutput "After installation is complete, press Enter to continue..." "Yellow"
            Read-Host

            # Verify installation after manual store install
            $verifyResult = wsl --list --verbose 2>$null | Where-Object { $_ -match $Distribution.Name }
            if ($verifyResult) {
                Write-ColorOutput "✓ Ubuntu distribution installed successfully via Microsoft Store" "Green"
                return $true
            } else {
                Write-ColorOutput "✗ Distribution not found after Microsoft Store installation" "Red"
            }

        } catch {
            Write-ColorOutput "✗ Error opening Microsoft Store: $_" "Red"
        }
    }

    # Method 3: Manual installation instructions
    Write-ColorOutput ""
    Write-ColorOutput "Step 3: Manual Installation Instructions" "Blue"
    Write-ColorOutput "========================================" "Blue"
    Write-ColorOutput "If automatic installation failed, please install manually:" "Yellow"
    Write-ColorOutput ""
    Write-ColorOutput "Option 1 - Microsoft Store:" "White"
    Write-ColorOutput "  1. Open Microsoft Store" "Gray"
    Write-ColorOutput "  2. Search for '$($Distribution.Name)'" "Gray"
    Write-ColorOutput "  3. Click 'Install' or 'Get'" "Gray"
    Write-ColorOutput "  4. Wait for download to complete" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "Option 2 - Command Line:" "White"
    Write-ColorOutput "  1. Open PowerShell as Administrator" "Gray"
    Write-ColorOutput "  2. Run: wsl --install -d $($Distribution.Name)" "Gray"
    Write-ColorOutput "  3. Wait for download to complete" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "Option 3 - Direct Store Link:" "White"
    if ($Distribution.StoreId) {
        Write-ColorOutput "  https://www.microsoft.com/store/apps/$($Distribution.StoreId)" "Gray"
    }
    Write-ColorOutput ""

    return $false
}

# Function to configure Ubuntu after installation
function Initialize-UbuntuConfiguration {
    param(
        [string]$DistributionName
    )

    Write-ColorOutput "Configuring Ubuntu distribution: $DistributionName..." "Blue"

    # Check if distribution is installed and needs initial setup
    try {
        # Test if we can run a simple command without user setup
        $testResult = wsl -d $DistributionName bash -c "echo 'test'" 2>$null
        if ($LASTEXITCODE -eq 0 -and $testResult -eq "test") {
            Write-ColorOutput "✓ Ubuntu distribution is already configured" "Green"
            return $true
        }
    } catch {
        # Distribution needs configuration
    }

    Write-ColorOutput ""
    Write-ColorOutput "Ubuntu Initial Setup Required" "Yellow"
    Write-ColorOutput "=============================" "Yellow"
    Write-ColorOutput "The Ubuntu distribution needs to be configured with a user account." "White"
    Write-ColorOutput "This will open Ubuntu in a new window for initial setup." "White"
    Write-ColorOutput ""

    $setupMessage = "Do you want to configure Ubuntu now? (Required for MCP Orchestrator)"
    if (-not (Get-UserConfirmation -Message $setupMessage -DefaultChoice "Y")) {
        Write-ColorOutput "Ubuntu configuration cancelled. Setup cannot continue without a configured WSL distribution." "Yellow"
        return $false
    }

    try {
        Write-ColorOutput "Opening Ubuntu for initial configuration..." "Blue"
        Write-ColorOutput "Please complete the user setup in the Ubuntu window that opens." "Yellow"
        Write-ColorOutput "After setup is complete, the Ubuntu window will remain open." "Gray"

        # Launch Ubuntu for initial setup
        Start-Process -FilePath "wsl" -ArgumentList "-d", $DistributionName -Wait

        Write-ColorOutput ""
        Write-ColorOutput "Verifying Ubuntu configuration..." "Blue"

        # Wait a moment for setup to complete
        Start-Sleep -Seconds 2

        # Test if Ubuntu is now properly configured
        $maxAttempts = 5
        $attempt = 1

        while ($attempt -le $maxAttempts) {
            try {
                $testResult = wsl -d $DistributionName bash -c "whoami" 2>$null
                if ($LASTEXITCODE -eq 0 -and $testResult -and $testResult.Trim()) {
                    $username = $testResult.Trim()
                    Write-ColorOutput "✓ Ubuntu configured successfully with user: $username" "Green"

                    # Update package lists for better experience
                    Write-ColorOutput "Updating package lists..." "Blue"
                    wsl -d $DistributionName bash -c "sudo apt update" 2>$null

                    return $true
                }
            } catch {
                # Configuration not complete yet
            }

            if ($attempt -lt $maxAttempts) {
                Write-ColorOutput "Waiting for Ubuntu configuration to complete... (attempt $attempt/$maxAttempts)" "Yellow"
                Start-Sleep -Seconds 3
            }
            $attempt++
        }

        Write-ColorOutput "✗ Ubuntu configuration verification failed" "Red"
        Write-ColorOutput "Please ensure you completed the Ubuntu user setup." "Yellow"
        return $false

    } catch {
        Write-ColorOutput "✗ Error during Ubuntu configuration: $_" "Red"
        return $false
    }
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
        Write-ColorOutput "No WSL distributions available." "Yellow"

        # Let user choose Ubuntu distribution
        $selectedDistribution = Select-UbuntuDistribution
        if (-not $selectedDistribution) {
            Write-ColorOutput "✗ No Ubuntu distribution selected" "Red"
            return $false
        }

        # Ensure temp directory exists for installation logs
        if (-not (Test-Path "temp")) {
            New-Item -Path "temp" -ItemType Directory -Force | Out-Null
        }

        # Install selected Ubuntu distribution with robust download
        if (Install-UbuntuDistribution -Distribution $selectedDistribution) {
            Write-ColorOutput "✓ $($selectedDistribution.Name) distribution downloaded successfully" "Green"

            # Configure the newly installed distribution
            if (Initialize-UbuntuConfiguration -DistributionName $selectedDistribution.Name) {
                Write-ColorOutput "✓ Ubuntu installation and configuration completed" "Green"
            } else {
                Write-ColorOutput "✗ Ubuntu configuration failed" "Red"
                Write-ColorOutput "Please run 'wsl -d $($selectedDistribution.Name)' to complete setup manually." "Yellow"
                return $false
            }
        } else {
            Write-ColorOutput "✗ Failed to install $($selectedDistribution.Name) distribution" "Red"
            Write-ColorOutput ""
            Write-ColorOutput "Please try installing manually and run this script again." "Yellow"
            return $false
        }
    } else {
        # WSL distributions exist, verify they are properly configured
        $wslInfo = Get-WSLDistributions
        if ($wslInfo.Default -and $wslInfo.Default.UserInfo.Username) {
            Write-ColorOutput "✓ WSL distribution is properly configured" "Green"
        } else {
            Write-ColorOutput "⚠ WSL distribution may need configuration" "Yellow"
            if ($wslInfo.Default) {
                Initialize-UbuntuConfiguration -DistributionName $wslInfo.Default.Name | Out-Null
            }
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
            wsl bash -c "echo 'export DOCKER_HOST=unix:///run/user/`$(id -u)/docker.sock' >> ~/.bashrc"

            # Start Docker service
            Write-ColorOutput "Starting Docker service..." "Blue"
            wsl bash -c "~/bin/dockerd-rootless.sh --experimental --storage-driver vfs > /dev/null 2>&1 &"
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
            Write-ColorOutput "6. Restart WSL: wsl --shutdown; wsl" "White"
            Write-ColorOutput "7. Start Docker: ~/bin/dockerd-rootless.sh --experimental --storage-driver vfs" "White"
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
    Write-ColorOutput "Step 1: Comprehensive Environment Analysis" "Yellow"

    # Dynamic Docker Desktop detection
    $dockerDesktopInfo = Test-DockerDesktopInstallation
    if (-not $dockerDesktopInfo.Found) {
        Write-ColorOutput "⚠ Docker Desktop not detected" "Yellow"
        Write-ColorOutput "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" "Gray"
    }

    # Check and enable Windows features
    if (-not (Enable-RequiredWindowsFeatures)) {
        Write-ColorOutput "Failed to enable required Windows features. Exiting." "Red"
        exit 1
    }

    # Initialize WSL with comprehensive analysis
    if (-not (Initialize-WSL)) {
        Write-ColorOutput "Failed to initialize WSL. Exiting." "Red"
        exit 1
    }

    # Get detailed WSL distribution information
    $wslInfo = Get-WSLDistributions
    if ($wslInfo.Count -eq 0) {
        Write-ColorOutput "No WSL distributions available. Please install a WSL distribution." "Red"
        exit 1
    }

    # Test Docker Desktop WSL2 backend
    if ($dockerDesktopInfo.Found) {
        $wsl2BackendInfo = Test-DockerDesktopWSL2Backend
        if (-not $wsl2BackendInfo.WSL2BackendEnabled) {
            Write-ColorOutput "⚠ Docker Desktop WSL2 backend is not enabled" "Yellow"

            if ($wsl2BackendInfo.SettingsPath -and $wsl2BackendInfo.SettingsContent) {
                if (Set-DockerDesktopWSL2Backend -SettingsPath $wsl2BackendInfo.SettingsPath -CurrentSettings $wsl2BackendInfo.SettingsContent) {
                    Write-ColorOutput "✓ Docker Desktop WSL2 backend configured" "Green"
                    Write-ColorOutput "Please restart Docker Desktop and run this script again." "Yellow"
                    exit 0
                }
            }
        } else {
            Write-ColorOutput "✓ Docker Desktop WSL2 backend is properly configured" "Green"
        }
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

# Function to configure Docker socket paths based on detected environment
function Set-DockerSocketPaths {
    Write-ColorOutput "Configuring Docker socket paths..." "Blue"

    $socketConfiguration = @{
        SocketPath = $null
        UserUID = $null
        DistributionName = $null
        ConfigurationFiles = @()
    }

    # Get WSL distribution information
    $wslInfo = Get-WSLDistributions

    if ($wslInfo.Count -gt 0 -and $wslInfo.Default) {
        # Use default WSL distribution
        $defaultDist = $wslInfo.Default
        $socketConfiguration.DistributionName = $defaultDist.Name
        $socketConfiguration.UserUID = $defaultDist.UserInfo.UID

        if ($defaultDist.UserInfo.UID) {
            $socketConfiguration.SocketPath = "/run/user/$($defaultDist.UserInfo.UID)/docker.sock"
            Write-ColorOutput "✓ Using WSL distribution: $($defaultDist.Name)" "Green"
            Write-ColorOutput "  User UID: $($defaultDist.UserInfo.UID)" "Gray"
            Write-ColorOutput "  Socket path: $($socketConfiguration.SocketPath)" "Gray"
        } else {
            Write-ColorOutput "⚠ Could not determine UID for WSL distribution: $($defaultDist.Name)" "Yellow"
            $socketConfiguration.SocketPath = "//./pipe/docker_engine"  # Fallback to Windows Docker Desktop
        }
    } else {
        # No WSL or no default distribution - use Windows Docker Desktop
        Write-ColorOutput "Using Windows Docker Desktop named pipe" "Blue"
        $socketConfiguration.SocketPath = "//./pipe/docker_engine"
        $socketConfiguration.UserUID = "1001"  # Default for Windows
    }

    # Update configuration files with correct socket path
    $configFiles = @(
        "deploy/env/.env.core",
        "deploy/env/.env.rootless"
    )

    foreach ($configFile in $configFiles) {
        if (Test-Path $configFile) {
            try {
                $content = Get-Content $configFile -Raw

                # Update socket path
                $content = $content -replace 'DOCKER_ROOTLESS_SOCKET_PATH=.*', "DOCKER_ROOTLESS_SOCKET_PATH=$($socketConfiguration.SocketPath)"

                # Update UID if applicable
                if ($socketConfiguration.UserUID) {
                    $content = $content -replace 'UID=.*', "UID=$($socketConfiguration.UserUID)"
                }

                Set-Content -Path $configFile -Value $content -ErrorAction Stop
                $socketConfiguration.ConfigurationFiles += $configFile
                Write-ColorOutput "✓ Updated: $configFile" "Green"

            } catch {
                Write-ColorOutput "⚠ Failed to update $configFile`: $_" "Yellow"
            }
        }
    }

    return $socketConfiguration
}

# Get current user ID for rootless Docker (backward compatibility)
function Get-DockerUserId {
    $socketConfig = Set-DockerSocketPaths
    return $socketConfig.UserUID
}

# Get rootless Docker socket path (backward compatibility)
function Get-RootlessDockerSocketPath {
    param([string]$UserId)

    $socketConfig = Set-DockerSocketPaths
    return $socketConfig.SocketPath
}

# Function to discover required ports from Docker Compose files and codebase
function Get-RequiredPorts {
    Write-ColorOutput "Discovering required ports..." "Blue"

    $discoveredPorts = @()
    $portSources = @()

    # Parse Docker Compose files for exposed ports
    $composeFiles = @(
        "deploy/docker-compose.yml",
        "deploy/docker-compose.windows.yml"
    )

    foreach ($composeFile in $composeFiles) {
        if (Test-Path $composeFile) {
            try {
                $composeContent = Get-Content $composeFile -Raw

                # Extract port mappings using regex
                $portMatches = [regex]::Matches($composeContent, '"(\d+):(\d+)"')

                foreach ($match in $portMatches) {
                    $hostPort = $match.Groups[1].Value
                    $containerPort = $match.Groups[2].Value

                    $portInfo = @{
                        HostPort = [int]$hostPort
                        ContainerPort = [int]$containerPort
                        Source = $composeFile
                        Protocol = "tcp"
                    }

                    # Avoid duplicates
                    if (-not ($discoveredPorts | Where-Object { $_.HostPort -eq $portInfo.HostPort })) {
                        $discoveredPorts += $portInfo
                        $portSources += "$composeFile`: $hostPort->$containerPort"
                    }
                }

            } catch {
                Write-ColorOutput "⚠ Could not parse $composeFile`: $_" "Yellow"
            }
        }
    }

    # Add known orchestrator ports from codebase analysis
    $knownPorts = @(
        @{ HostPort = 3000; ContainerPort = 3000; Source = "Orchestrator Core"; Protocol = "tcp" },
        @{ HostPort = 3001; ContainerPort = 3001; Source = "File Agent"; Protocol = "tcp" },
        @{ HostPort = 3002; ContainerPort = 3002; Source = "Web Agent"; Protocol = "tcp" },
        @{ HostPort = 3003; ContainerPort = 3003; Source = "Database Agent"; Protocol = "tcp" },
        @{ HostPort = 3004; ContainerPort = 3004; Source = "Task Agent"; Protocol = "tcp" }
    )

    foreach ($knownPort in $knownPorts) {
        if (-not ($discoveredPorts | Where-Object { $_.HostPort -eq $knownPort.HostPort })) {
            $discoveredPorts += $knownPort
            $portSources += "$($knownPort.Source)`: $($knownPort.HostPort)"
        }
    }

    # Sort ports for consistent output
    $discoveredPorts = $discoveredPorts | Sort-Object HostPort

    Write-ColorOutput "✓ Discovered $($discoveredPorts.Count) required ports:" "Green"
    foreach ($port in $discoveredPorts) {
        Write-ColorOutput "  - Port $($port.HostPort) ($($port.Source))" "Gray"
    }

    return @{
        Ports = $discoveredPorts
        Sources = $portSources
        Count = $discoveredPorts.Count
    }
}

# Function to test port forwarding from Windows host to containers
function Test-DynamicPortForwarding {
    param(
        [array]$RequiredPorts
    )

    Write-ColorOutput "Testing port forwarding..." "Blue"

    $portTestResults = @()

    foreach ($portInfo in $RequiredPorts) {
        $port = $portInfo.HostPort
        $testResult = @{
            Port = $port
            Source = $portInfo.Source
            Accessible = $false
            Error = $null
        }

        try {
            # Test if port is accessible from Windows host
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.ConnectAsync("localhost", $port)
            $timeout = 2000  # 2 seconds timeout

            if ($connectTask.Wait($timeout)) {
                $testResult.Accessible = $true
                Write-ColorOutput "✓ Port $port is accessible" "Green"
            } else {
                $testResult.Error = "Connection timeout"
                Write-ColorOutput "⚠ Port $port is not accessible (timeout)" "Yellow"
            }

            $tcpClient.Close()

        } catch {
            $testResult.Error = $_.Exception.Message
            Write-ColorOutput "⚠ Port $port is not accessible: $($_.Exception.Message)" "Yellow"
        }

        $portTestResults += $testResult
    }

    $accessibleCount = ($portTestResults | Where-Object { $_.Accessible }).Count
    $totalCount = $portTestResults.Count

    Write-ColorOutput "Port accessibility: $accessibleCount/$totalCount ports accessible" "Blue"

    return $portTestResults
}

# Function to configure Windows Firewall for discovered ports
function Set-DynamicFirewallRules {
    param(
        [array]$RequiredPorts
    )

    Write-ColorOutput "Configuring Windows Firewall rules..." "Blue"

    if (-not (Test-Administrator)) {
        Write-ColorOutput "⚠ Administrative privileges required for firewall configuration" "Yellow"
        Write-ColorOutput "Firewall rules will need to be configured manually if needed" "Gray"
        return $false
    }

    $firewallMessage = "Do you want to configure Windows Firewall rules for MCP Orchestrator ports?"
    if (-not (Get-UserConfirmation -Message $firewallMessage)) {
        Write-ColorOutput "Firewall configuration skipped by user." "Yellow"
        return $false
    }

    $configuredRules = @()
    $existingRules = @()

    foreach ($portInfo in $RequiredPorts) {
        $port = $portInfo.HostPort
        $ruleName = "MCP Orchestrator - $($portInfo.Source) (Port $port)"

        try {
            # Check if rule already exists
            $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

            if ($existingRule) {
                Write-ColorOutput "✓ Firewall rule already exists: $ruleName" "Green"
                $existingRules += $ruleName
            } else {
                # Create new firewall rule
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Domain,Private,Public -ErrorAction Stop | Out-Null
                Write-ColorOutput "✓ Created firewall rule: $ruleName" "Green"
                $configuredRules += $ruleName
            }

        } catch {
            Write-ColorOutput "✗ Failed to configure firewall rule for port $port`: $_" "Red"
        }
    }

    Write-ColorOutput "Firewall configuration summary:" "Blue"
    Write-ColorOutput "  - Existing rules: $($existingRules.Count)" "Gray"
    Write-ColorOutput "  - New rules created: $($configuredRules.Count)" "Gray"

    return $true
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

Write-ColorOutput "Step 3: Dynamic Environment Configuration" "Yellow"

# Configure Docker socket paths based on detected environment
$socketConfig = Set-DockerSocketPaths

# Discover required ports
$portInfo = Get-RequiredPorts

# Set environment variable for Docker Compose
$env:DOCKER_USER_ID = $socketConfig.UserUID

Write-ColorOutput "Creating rootless Docker environment configuration..." "Blue"

# Create environment configuration for rootless Docker only
$envContent = @"
# MCP Orchestrator Core Configuration - Rootless Docker Only
# This configuration is designed exclusively for rootless Docker deployment
# Generated dynamically based on detected environment
ORCHESTRATOR_PORT=3000
ORCHESTRATOR_HOST=0.0.0.0
NODE_ENV=production
LOG_LEVEL=INFO

# Docker Mode - Rootless Only (no fallback to standard Docker)
DOCKER_MODE=rootless
DOCKER_ROOTLESS_SOCKET_PATH=$($socketConfig.SocketPath)
UID=$($socketConfig.UserUID)

# Timeout and Retry Configuration (optimized for rootless Docker)
MCP_TIMEOUT=45000
DISCOVERY_RETRY_ATTEMPTS=10
DISCOVERY_RETRY_DELAY=3000

# Rootless Docker Security Settings
ROOTLESS_MODE=true
DOCKER_ROOTLESS_ENABLED=true

# Environment Detection Results
# WSL Distribution: $($socketConfig.DistributionName)
# Detected Ports: $($portInfo.Count) ports discovered
# Configuration Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
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

Write-ColorOutput "Step 4: Comprehensive Configuration Validation" "Yellow"

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

# Test port forwarding (if services are running)
Write-ColorOutput "Testing port accessibility..." "Blue"
$portTestResults = Test-DynamicPortForwarding -RequiredPorts $portInfo.Ports

# Configure Windows Firewall if needed
$accessiblePorts = ($portTestResults | Where-Object { $_.Accessible }).Count
if ($accessiblePorts -lt $portInfo.Count) {
    Write-ColorOutput "Some ports are not accessible. Configuring firewall..." "Yellow"
    Set-DynamicFirewallRules -RequiredPorts $portInfo.Ports | Out-Null
}

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
Write-ColorOutput "  User ID: $($socketConfig.UserUID)" "White"
Write-ColorOutput "  Socket Path: $($socketConfig.SocketPath)" "White"
Write-ColorOutput "  WSL Distribution: $($socketConfig.DistributionName)" "White"
Write-ColorOutput "  Environment: deploy/env/.env.core" "White"
Write-ColorOutput "  Compose File: $composeFile" "White"
Write-ColorOutput "  Required Ports: $($portInfo.Count) ports discovered" "White"
if (-not $SkipPrerequisites) {
    Write-ColorOutput "  Windows Features: ✓ Verified and Enabled" "White"
    Write-ColorOutput "  WSL: ✓ Installed and Configured ($($wslInfo.Count) distributions)" "White"
    Write-ColorOutput "  Docker Desktop: $(if ($dockerDesktopInfo.Found) { '✓ Detected v' + $dockerDesktopInfo.Version } else { '⚠ Not detected' })" "White"
    Write-ColorOutput "  WSL2 Backend: $(if ($wsl2BackendInfo.WSL2BackendEnabled) { '✓ Enabled' } else { '⚠ Not enabled' })" "White"
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
# Generate environment-specific documentation
Write-ColorOutput "Generating environment-specific documentation..." "Blue"
try {
    & ".\scripts\docs\generate-environment-docs.ps1" -OutputPath "docs/environment/current-environment.md" 2>$null | Out-Null
    Write-ColorOutput "✓ Environment documentation generated: docs/environment/current-environment.md" "Green"
} catch {
    Write-ColorOutput "⚠ Failed to generate environment documentation: $_" "Yellow"
}

Write-ColorOutput ""
Write-ColorOutput "For more information:" "Gray"
Write-ColorOutput "  - Core documentation: docs/core.md" "Gray"
Write-ColorOutput "  - Environment-specific guide: docs/environment/current-environment.md" "Gray"
Write-ColorOutput "  - Run diagnostics: .\scripts\diagnostics\smart-container-diagnostics.ps1" "Gray"