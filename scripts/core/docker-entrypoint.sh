#!/bin/bash

# MCP Orchestrator Docker Entrypoint Script
# Handles dynamic permission setup for rootless Docker access
# Moved to scripts/core/ for better organization per NEOMINT-RESEARCH guidelines

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

print_color $BLUE "MCP Orchestrator Container Starting..."

# Get current user info
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

print_color $GREEN "Container user: $(whoami) (UID: $CURRENT_UID, GID: $CURRENT_GID)"

# Check if UID environment variable is set (from docker-compose)
if [ -n "$UID" ] && [ "$UID" != "$CURRENT_UID" ]; then
    print_color $YELLOW "Warning: Container UID ($CURRENT_UID) differs from expected UID ($UID)"
    print_color $YELLOW "This may cause permission issues with rootless Docker socket"
fi

# Function to check and report Docker socket access
check_docker_socket() {
    local socket_path="$1"
    local socket_type="$2"
    
    if [ -S "$socket_path" ]; then
        print_color $GREEN "Found $socket_type Docker socket: $socket_path"
        
        # Check if we can access the socket
        if [ -r "$socket_path" ] && [ -w "$socket_path" ]; then
            print_color $GREEN "Socket is accessible for read/write"
            return 0
        else
            print_color $YELLOW "Socket exists but may not be accessible (permissions: $(ls -la "$socket_path" 2>/dev/null | awk '{print $1}'))"
            return 1
        fi
    else
        print_color $BLUE "$socket_type Docker socket not found at: $socket_path"
        return 1
    fi
}

# Check for rootless Docker sockets only
print_color $BLUE "Checking rootless Docker socket availability..."

DOCKER_AVAILABLE=false

# Check rootless Docker sockets
ROOTLESS_PATHS=(
    "/run/user/$CURRENT_UID/docker.sock"
    "/run/user/${UID:-$CURRENT_UID}/docker.sock"
    "/tmp/docker-$CURRENT_UID/docker.sock"
    "/tmp/docker-${UID:-$CURRENT_UID}/docker.sock"
)

for socket_path in "${ROOTLESS_PATHS[@]}"; do
    if check_docker_socket "$socket_path" "rootless"; then
        DOCKER_AVAILABLE=true
        # Set environment variable for the application
        export DOCKER_ROOTLESS_SOCKET_PATH="$socket_path"
        print_color $GREEN "Found rootless Docker socket at: $socket_path"
        break
    fi
done

# Check if rootless Docker socket is available
if [ "$DOCKER_AVAILABLE" = false ]; then
    print_color $RED "Error: No accessible rootless Docker sockets found"
    print_color $YELLOW "Please ensure rootless Docker is installed and running"
    print_color $YELLOW "See: https://docs.docker.com/engine/security/rootless/"
    exit 1
else
    print_color $GREEN "Rootless Docker socket access verified"
fi

# Set dynamic environment variables
if [ -n "$UID" ]; then
    export DOCKER_ROOTLESS_SOCKET_PATH="/run/user/$UID/docker.sock"
    print_color $BLUE "Set DOCKER_ROOTLESS_SOCKET_PATH to: $DOCKER_ROOTLESS_SOCKET_PATH"
fi

# Display environment info
print_color $BLUE "Environment Configuration:"
print_color $BLUE "  DOCKER_MODE: ${DOCKER_MODE:-rootless}"
print_color $BLUE "  DOCKER_ROOTLESS_SOCKET_PATH: ${DOCKER_ROOTLESS_SOCKET_PATH:-not set}"
print_color $BLUE "  LOG_LEVEL: ${LOG_LEVEL:-INFO}"
print_color $BLUE "  ROOTLESS_MODE: ${ROOTLESS_MODE:-true}"

print_color $GREEN "Starting MCP Orchestrator..."

# Execute the main command
exec "$@"
