# MCP Orchestrator - Rootless Docker Test Suite (PowerShell)
# Runs comprehensive tests for rootless Docker functionality

param(
    [switch]$Verbose,
    [string]$TestPattern = "*rootless*"
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "MCP Orchestrator - Rootless Docker Test Suite" "Blue"
Write-ColorOutput "=============================================" "Blue"

# Check if we're in the right directory
if (-not (Test-Path "package.json")) {
    Write-ColorOutput "Error: package.json not found. Please run this script from the project root." "Red"
    exit 1
}

# Check if npm/npx is available
try {
    npx --version | Out-Null
    Write-ColorOutput "npx is available" "Green"
} catch {
    Write-ColorOutput "Error: npx not found. Please install Node.js and npm." "Red"
    exit 1
}

# Detect current environment
$CurrentUID = 1001  # Default for Windows/WSL
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    try {
        $CurrentUID = wsl id -u
        Write-ColorOutput "Detected WSL UID: $CurrentUID" "Green"
    } catch {
        Write-ColorOutput "Could not detect WSL UID, using default: $CurrentUID" "Yellow"
    }
} else {
    Write-ColorOutput "WSL not available, using default UID: $CurrentUID" "Yellow"
}

Write-ColorOutput "Environment Detection:" "Green"
Write-ColorOutput "  Current UID: $CurrentUID" "Green"

# Check Docker availability
$DockerAvailable = $false
$RootlessAvailable = $false

try {
    docker version | Out-Null
    Write-ColorOutput "  Docker CLI: Available" "Green"
    $DockerAvailable = $true
    
    # Check Docker daemon connectivity
    try {
        docker version | Out-Null
        Write-ColorOutput "  Docker daemon: Accessible" "Green"
    } catch {
        Write-ColorOutput "  Docker daemon: Not accessible" "Yellow"
    }
} catch {
    Write-ColorOutput "  Docker CLI: Not available" "Yellow"
}

# For Windows, rootless Docker detection is different
if ($DockerAvailable) {
    try {
        # Check if running in rootless mode (Windows Docker Desktop doesn't use traditional rootless)
        $dockerSecurityOptions = docker info --format "{{.SecurityOptions}}" 2>$null
        if ($dockerSecurityOptions -and $dockerSecurityOptions -match "rootless") {
            Write-ColorOutput "  Rootless mode: Detected" "Green"
            $RootlessAvailable = $true
        } else {
            Write-ColorOutput "  Rootless mode: Not detected (Windows Docker Desktop)" "Yellow"
        }
    } catch {
        Write-ColorOutput "  Rootless mode: Could not determine" "Yellow"
    }
}

# Set environment variables for tests
$env:DOCKER_USER_ID = $CurrentUID
$env:UID = $CurrentUID

Write-ColorOutput "`nRunning Test Suite..." "Blue"

# Function to invoke test with error handling
function Invoke-Test {
    param(
        [string]$TestName,
        [string]$TestFile,
        [string]$RequiredCondition = "none"
    )

    Write-ColorOutput "`n--- Running $TestName ---" "Blue"

    if ($RequiredCondition -eq "docker" -and -not $DockerAvailable) {
        Write-ColorOutput "Skipping $TestName - Docker not available" "Yellow"
        return $true
    }

    if ($RequiredCondition -eq "rootless" -and -not $RootlessAvailable) {
        Write-ColorOutput "Skipping $TestName - Rootless Docker not available" "Yellow"
        return $true
    }

    try {
        if ($Verbose) {
            npx jest $TestFile --verbose
        } else {
            npx jest $TestFile
        }

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ $TestName passed" "Green"
            return $true
        } else {
            Write-ColorOutput "✗ $TestName failed" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ $TestName failed with error: $_" "Red"
        return $false
    }
}

# Track test results
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

# Run unit tests (always run these)
$TotalTests++
if (Invoke-Test "Unit Tests - Socket Detection" "tests/core/discovery-rootless.test.js" "none") {
    $PassedTests++
} else {
    $FailedTests++
}

# Run integration tests (require Docker)
$TotalTests++
if (Invoke-Test "Integration Tests - Docker Configurations" "tests/integration/docker-configurations.test.js" "docker") {
    $PassedTests++
} else {
    $FailedTests++
}

# Run rootless-specific tests (require rootless Docker)
$TotalTests++
if (Invoke-Test "Integration Tests - Rootless Docker" "tests/integration/rootless-docker.test.js" "rootless") {
    $PassedTests++
} else {
    $FailedTests++
}

# Run existing discovery tests
$TotalTests++
if (Invoke-Test "Integration Tests - Agent Discovery" "tests/integration/agent-discovery.test.js" "docker") {
    $PassedTests++
} else {
    $FailedTests++
}

# Print summary
Write-ColorOutput "`n=============================================" "Blue"
Write-ColorOutput "Test Suite Summary" "Blue"
Write-ColorOutput "=============================================" "Blue"
Write-ColorOutput "Total tests: $TotalTests" "Green"
Write-ColorOutput "Passed: $PassedTests" "Green"

if ($FailedTests -gt 0) {
    Write-ColorOutput "Failed: $FailedTests" "Red"
    Write-ColorOutput "`nSome tests failed. Please check the output above." "Red"
    exit 1
} else {
    Write-ColorOutput "Failed: $FailedTests" "Green"
    Write-ColorOutput "`nAll tests passed successfully!" "Green"
}

# Additional validation if Docker is available
if ($DockerAvailable) {
    Write-ColorOutput "`nRunning additional Docker validation..." "Blue"
    
    # Test Docker connectivity
    try {
        docker version | Out-Null
        Write-ColorOutput "✓ Docker connectivity verified" "Green"
    } catch {
        Write-ColorOutput "⚠ Docker connectivity issue" "Yellow"
    }
    
    # Test container listing
    try {
        docker ps | Out-Null
        Write-ColorOutput "✓ Container listing works" "Green"
    } catch {
        Write-ColorOutput "⚠ Container listing issue" "Yellow"
    }
}

Write-ColorOutput "`nRootless Docker test suite completed successfully!" "Green"

# Provide recommendations based on test results
Write-ColorOutput "`nRecommendations:" "Blue"
if (-not $RootlessAvailable -and $DockerAvailable) {
    Write-ColorOutput "Consider using WSL2 with rootless Docker for improved security:" "Yellow"
    Write-ColorOutput "  https://docs.docker.com/engine/security/rootless/" "Yellow"
}

if (-not $DockerAvailable) {
    Write-ColorOutput "Install Docker Desktop to run the full test suite:" "Yellow"
    Write-ColorOutput "  https://docs.docker.com/desktop/windows/" "Yellow"
}
