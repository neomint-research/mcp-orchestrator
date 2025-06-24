# Test Script for Updated setup.ps1
# Tests the Docker mode selection functionality

param(
    [switch]$Verbose
)

function Write-TestResult {
    param(
        [bool]$Success,
        [string]$TestName,
        [string]$Details = ""
    )
    
    if ($Success) {
        Write-Host "✓ $TestName" -ForegroundColor Green
        if ($Details -and $Verbose) {
            Write-Host "  $Details" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ $TestName" -ForegroundColor Red
        if ($Details) {
            Write-Host "  $Details" -ForegroundColor Yellow
        }
    }
}

Write-Host "Testing setup.ps1 Docker Mode Selection" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

$testsPassed = 0
$totalTests = 0

# Test 1: Script syntax validation
$totalTests++
try {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content setup.ps1 -Raw), [ref]$null)
    Write-TestResult $true "PowerShell syntax validation"
    $testsPassed++
} catch {
    Write-TestResult $false "PowerShell syntax validation" $_.Exception.Message
}

# Test 2: Parameter validation
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasDockerModeParam = $setupScript -match '\[ValidateSet\("auto", "standard", "rootless"\)\]'
    Write-TestResult $hasDockerModeParam "DockerMode parameter validation"
    if ($hasDockerModeParam) { $testsPassed++ }
} catch {
    Write-TestResult $false "DockerMode parameter validation" $_.Exception.Message
}

# Test 3: Function definitions
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasRootlessTest = $setupScript -match 'function Test-RootlessDockerAvailability'
    $hasDockerModeSelect = $setupScript -match 'function Select-DockerMode'
    $hasBothFunctions = $hasRootlessTest -and $hasDockerModeSelect
    Write-TestResult $hasBothFunctions "Required function definitions"
    if ($hasBothFunctions) { $testsPassed++ }
} catch {
    Write-TestResult $false "Required function definitions" $_.Exception.Message
}

# Test 4: Environment configuration logic
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasRootlessConfig = $setupScript -match 'DOCKER_MODE=rootless'
    $hasStandardConfig = $setupScript -match 'DOCKER_MODE=auto'
    $hasBothConfigs = $hasRootlessConfig -and $hasStandardConfig
    Write-TestResult $hasBothConfigs "Environment configuration for both modes"
    if ($hasBothConfigs) { $testsPassed++ }
} catch {
    Write-TestResult $false "Environment configuration for both modes" $_.Exception.Message
}

# Test 5: Docker compose file selection
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasComposeFileVar = $setupScript -match '\$script:DockerComposeFile'
    $hasRootlessCompose = $setupScript -match 'docker-compose\.rootless\.yml'
    $hasComposeSelection = $hasComposeFileVar -and $hasRootlessCompose
    Write-TestResult $hasComposeSelection "Docker compose file selection logic"
    if ($hasComposeSelection) { $testsPassed++ }
} catch {
    Write-TestResult $false "Docker compose file selection logic" $_.Exception.Message
}

# Test 6: Help documentation
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasHelpBlock = $setupScript -match '<#[\s\S]*\.SYNOPSIS[\s\S]*#>'
    $hasExamples = $setupScript -match '\.EXAMPLE'
    $hasDocumentation = $hasHelpBlock -and $hasExamples
    Write-TestResult $hasDocumentation "Help documentation and examples"
    if ($hasDocumentation) { $testsPassed++ }
} catch {
    Write-TestResult $false "Help documentation and examples" $_.Exception.Message
}

# Test 7: Error handling
$totalTests++
try {
    $setupScript = Get-Content setup.ps1 -Raw
    $hasTryCatch = $setupScript -match 'try\s*\{[\s\S]*\}\s*catch'
    $hasErrorMessages = $setupScript -match 'Rootless Docker.*not available'
    $hasErrorHandling = $hasTryCatch -and $hasErrorMessages
    Write-TestResult $hasErrorHandling "Error handling for unavailable modes"
    if ($hasErrorHandling) { $testsPassed++ }
} catch {
    Write-TestResult $false "Error handling for unavailable modes" $_.Exception.Message
}

# Summary
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

$successRate = [math]::Round(($testsPassed / $totalTests) * 100, 1)

Write-Host "Tests Passed: $testsPassed/$totalTests ($successRate%)" -ForegroundColor $(if ($testsPassed -eq $totalTests) { "Green" } else { "Yellow" })

if ($testsPassed -eq $totalTests) {
    Write-Host "✓ All tests passed! The setup.ps1 script is ready for use." -ForegroundColor Green
    Write-Host "`nUsage examples:" -ForegroundColor Cyan
    Write-Host "  .\setup.ps1                    # Interactive mode with auto-detection" -ForegroundColor White
    Write-Host "  .\setup.ps1 -DockerMode rootless  # Force rootless mode" -ForegroundColor White
    Write-Host "  .\setup.ps1 -DockerMode standard  # Force standard mode" -ForegroundColor White
    Write-Host "  Get-Help .\setup.ps1 -Full        # View complete help" -ForegroundColor White
} else {
    Write-Host "⚠ Some tests failed. Please review the script." -ForegroundColor Yellow
}

# Test help functionality
Write-Host "`nTesting help functionality..." -ForegroundColor Cyan
try {
    $helpOutput = Get-Help .\setup.ps1 -ErrorAction Stop
    if ($helpOutput.Synopsis) {
        Write-Host "✓ Help system working correctly" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "Synopsis: $($helpOutput.Synopsis)" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠ Help system available but no synopsis found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Help system test failed: $($_.Exception.Message)" -ForegroundColor Red
}

exit $(if ($testsPassed -eq $totalTests) { 0 } else { 1 })
