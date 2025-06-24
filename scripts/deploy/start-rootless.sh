#!/bin/bash

# MCP Orchestrator - Unix/Linux Rootless Docker Startup Script
# This script automatically detects the current user's UID and starts the orchestrator in rootless mode
# Designed for Unix/Linux systems with rootless Docker deployment
# For Windows Docker Desktop, use start-rootless.ps1 instead
# Moved to scripts/deploy/ for better organization per NEOMINT-RESEARCH guidelines

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

print_color $BLUE "MCP Orchestrator - Rootless Docker Setup"
print_color $BLUE "========================================"

# Check if we're in the right directory
if [ ! -f "deploy/docker-compose.yml" ]; then
    print_color $RED "Error: docker-compose.yml not found. Please run this script from the project root."
    exit 1
fi

# Detect current user ID
CURRENT_UID=$(id -u)
print_color $GREEN "Detected current user ID: $CURRENT_UID"

# Check if rootless Docker is available
ROOTLESS_SOCKET="/run/user/$CURRENT_UID/docker.sock"
if [ ! -S "$ROOTLESS_SOCKET" ]; then
    print_color $YELLOW "Warning: Rootless Docker socket not found at $ROOTLESS_SOCKET"
    print_color $YELLOW "Please ensure rootless Docker is installed and running."
    print_color $YELLOW "See: https://docs.docker.com/engine/security/rootless/"
    
    # Check for alternative locations
    ALT_SOCKET="/tmp/docker-$CURRENT_UID/docker.sock"
    if [ -S "$ALT_SOCKET" ]; then
        print_color $GREEN "Found alternative rootless Docker socket at $ALT_SOCKET"
        ROOTLESS_SOCKET="$ALT_SOCKET"
    else
        print_color $RED "No rootless Docker socket found. Exiting."
        exit 1
    fi
fi

print_color $GREEN "Using rootless Docker socket: $ROOTLESS_SOCKET"

# Export environment variables
export DOCKER_USER_ID=$CURRENT_UID
export DOCKER_HOST="unix://$ROOTLESS_SOCKET"

print_color $BLUE "Starting MCP Orchestrator in rootless mode..."
print_color $BLUE "User ID: $DOCKER_USER_ID"
print_color $BLUE "Docker Socket: $ROOTLESS_SOCKET"

# Change to deploy directory
cd deploy

# Start the services using the main docker-compose.yml (now rootless-only)
if [ "$1" = "--build" ]; then
    print_color $YELLOW "Building and starting services..."
    docker-compose up --build "$@"
elif [ "$1" = "-d" ] || [ "$1" = "--detach" ]; then
    print_color $YELLOW "Starting services in detached mode..."
    docker-compose up -d
    print_color $GREEN "Services started successfully!"
    print_color $BLUE "Check status with: docker-compose ps"
    print_color $BLUE "View logs with: docker-compose logs -f"
else
    print_color $YELLOW "Starting services..."
    docker-compose up "$@"
fi
