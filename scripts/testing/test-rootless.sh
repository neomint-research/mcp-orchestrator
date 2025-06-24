#!/bin/bash

# MCP Orchestrator - Rootless Docker Test Suite
# Runs comprehensive tests for rootless Docker functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

print_color $BLUE "MCP Orchestrator - Rootless Docker Test Suite"
print_color $BLUE "============================================="

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_color $RED "Error: package.json not found. Please run this script from the project root."
    exit 1
fi

# Check if Jest is available
if ! command -v npx &> /dev/null; then
    print_color $RED "Error: npx not found. Please install Node.js and npm."
    exit 1
fi

# Detect current environment
CURRENT_UID=$(id -u)
ROOTLESS_SOCKET="/run/user/$CURRENT_UID/docker.sock"

print_color $GREEN "Environment Detection:"
print_color $GREEN "  Current UID: $CURRENT_UID"
print_color $GREEN "  Rootless socket: $ROOTLESS_SOCKET"

# Check Docker availability
DOCKER_AVAILABLE=false
ROOTLESS_AVAILABLE=false

if command -v docker &> /dev/null; then
    print_color $GREEN "  Docker CLI: Available"
    DOCKER_AVAILABLE=true
    
    # Check Docker daemon connectivity
    if docker version &> /dev/null; then
        print_color $GREEN "  Docker daemon: Accessible"
    else
        print_color $YELLOW "  Docker daemon: Not accessible"
    fi
else
    print_color $YELLOW "  Docker CLI: Not available"
fi

# Check socket availability
if [ -S "$ROOTLESS_SOCKET" ]; then
    print_color $GREEN "  Rootless Docker socket: Available"
    ROOTLESS_AVAILABLE=true
else
    print_color $YELLOW "  Rootless Docker socket: Not found"
fi

# Note: Standard Docker socket checking removed - rootless only

# Set environment variables for tests
export DOCKER_USER_ID=$CURRENT_UID
export UID=$CURRENT_UID

print_color $BLUE "\nRunning Test Suite..."

# Function to run test with error handling
run_test() {
    local test_name="$1"
    local test_file="$2"
    local required_condition="$3"
    
    print_color $BLUE "\n--- Running $test_name ---"
    
    if [ "$required_condition" = "docker" ] && [ "$DOCKER_AVAILABLE" = false ]; then
        print_color $YELLOW "Skipping $test_name - Docker not available"
        return 0
    fi
    
    if [ "$required_condition" = "rootless" ] && [ "$ROOTLESS_AVAILABLE" = false ]; then
        print_color $YELLOW "Skipping $test_name - Rootless Docker not available"
        return 0
    fi
    
    if [ "$required_condition" = "standard" ] && [ "$STANDARD_AVAILABLE" = false ]; then
        print_color $YELLOW "Skipping $test_name - Standard Docker not available"
        return 0
    fi
    
    if npx jest "$test_file" --verbose; then
        print_color $GREEN "✓ $test_name passed"
        return 0
    else
        print_color $RED "✗ $test_name failed"
        return 1
    fi
}

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Run unit tests (always run these)
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "Unit Tests - Socket Detection" "tests/core/discovery-rootless.test.js" "none"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Run integration tests (require Docker)
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "Integration Tests - Docker Configurations" "tests/integration/docker-configurations.test.js" "docker"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Run rootless-specific tests (require rootless Docker)
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "Integration Tests - Rootless Docker" "tests/integration/rootless-docker.test.js" "rootless"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Run existing discovery tests
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "Integration Tests - Agent Discovery" "tests/integration/agent-discovery.test.js" "docker"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Print summary
print_color $BLUE "\n============================================="
print_color $BLUE "Test Suite Summary"
print_color $BLUE "============================================="
print_color $GREEN "Total tests: $TOTAL_TESTS"
print_color $GREEN "Passed: $PASSED_TESTS"

if [ $FAILED_TESTS -gt 0 ]; then
    print_color $RED "Failed: $FAILED_TESTS"
    print_color $RED "\nSome tests failed. Please check the output above."
    exit 1
else
    print_color $GREEN "Failed: $FAILED_TESTS"
    print_color $GREEN "\nAll tests passed successfully!"
fi

# Additional validation if rootless Docker is available
if [ "$ROOTLESS_AVAILABLE" = true ]; then
    print_color $BLUE "\nRunning additional rootless validation..."
    
    # Test socket connectivity
    if DOCKER_HOST="unix://$ROOTLESS_SOCKET" docker version &> /dev/null; then
        print_color $GREEN "✓ Rootless Docker socket connectivity verified"
    else
        print_color $YELLOW "⚠ Rootless Docker socket connectivity issue"
    fi
    
    # Test container listing
    if DOCKER_HOST="unix://$ROOTLESS_SOCKET" docker ps &> /dev/null; then
        print_color $GREEN "✓ Container listing works with rootless Docker"
    else
        print_color $YELLOW "⚠ Container listing issue with rootless Docker"
    fi
fi

print_color $GREEN "\nRootless Docker test suite completed successfully!"

# Provide recommendations based on test results
print_color $BLUE "\nRecommendations:"
if [ "$ROOTLESS_AVAILABLE" = false ] && [ "$STANDARD_AVAILABLE" = true ]; then
    print_color $YELLOW "Consider setting up rootless Docker for improved security:"
    print_color $YELLOW "  https://docs.docker.com/engine/security/rootless/"
fi

if [ "$DOCKER_AVAILABLE" = false ]; then
    print_color $YELLOW "Install Docker to run the full test suite:"
    print_color $YELLOW "  https://docs.docker.com/get-docker/"
fi
