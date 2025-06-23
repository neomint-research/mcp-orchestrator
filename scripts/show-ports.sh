#!/bin/bash

# MCP Multi-Agent Orchestrator - Port Discovery Script
# Lists all MCP agent containers with their external ports

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print header
print_header() {
    echo
    print_color $BLUE "=== MCP Multi-Agent Orchestrator - Port Discovery ==="
    echo
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_color $RED "Error: Docker is not running or not accessible"
        exit 1
    fi
}

# Function to get MCP containers
get_mcp_containers() {
    docker ps --filter "label=mcp.server=true" --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || {
        print_color $RED "Error: Failed to query Docker containers"
        exit 1
    }
}

# Function to get orchestrator container
get_orchestrator_container() {
    docker ps --filter "label=mcp.orchestrator=true" --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || {
        print_color $RED "Error: Failed to query Docker containers"
        exit 1
    }
}

# Function to extract port mappings
extract_ports() {
    local container_id=$1
    local container_name=$2
    
    # Get detailed port information
    local port_info=$(docker port "$container_id" 2>/dev/null || echo "No ports exposed")
    
    if [ "$port_info" = "No ports exposed" ]; then
        echo "    No external ports"
    else
        echo "$port_info" | while read -r line; do
            if [ -n "$line" ]; then
                echo "    $line"
            fi
        done
    fi
}

# Function to get container labels
get_container_labels() {
    local container_id=$1
    docker inspect "$container_id" --format '{{range $key, $value := .Config.Labels}}{{$key}}={{$value}}{{"\n"}}{{end}}' 2>/dev/null | grep "mcp\." || echo "No MCP labels"
}

# Function to show detailed container info
show_container_details() {
    local container_id=$1
    local container_name=$2
    local image=$3
    local status=$4
    
    print_color $GREEN "Container: $container_name ($container_id)"
    echo "  Image: $image"
    echo "  Status: $status"
    
    # Show port mappings
    echo "  Port Mappings:"
    extract_ports "$container_id" "$container_name"
    
    # Show MCP-specific labels
    echo "  MCP Labels:"
    get_container_labels "$container_id" | while read -r label; do
        if [ -n "$label" ]; then
            echo "    $label"
        fi
    done
    
    # Try to get internal IP
    local internal_ip=$(docker inspect "$container_id" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    if [ -n "$internal_ip" ]; then
        echo "  Internal IP: $internal_ip"
    fi
    
    echo
}

# Function to test connectivity
test_connectivity() {
    local host=$1
    local port=$2
    local name=$3
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$host" "$port" 2>/dev/null; then
            print_color $GREEN "  ✓ $name is reachable at $host:$port"
        else
            print_color $RED "  ✗ $name is not reachable at $host:$port"
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout 3 telnet "$host" "$port" >/dev/null 2>&1; then
            print_color $GREEN "  ✓ $name is reachable at $host:$port"
        else
            print_color $RED "  ✗ $name is not reachable at $host:$port"
        fi
    else
        print_color $YELLOW "  ? Cannot test connectivity (nc or telnet not available)"
    fi
}

# Function to show quick summary
show_summary() {
    print_color $BLUE "=== Quick Summary ==="
    echo
    
    # Count containers
    local orchestrator_count=$(docker ps --filter "label=mcp.orchestrator=true" --quiet | wc -l)
    local agent_count=$(docker ps --filter "label=mcp.server=true" --quiet | wc -l)
    
    echo "Orchestrator containers: $orchestrator_count"
    echo "Agent containers: $agent_count"
    echo
    
    # Show key endpoints
    if [ "$orchestrator_count" -gt 0 ]; then
        print_color $GREEN "Key Endpoints:"
        
        # Try to find orchestrator port
        local orch_port=$(docker ps --filter "label=mcp.orchestrator=true" --format "{{.Ports}}" | head -1 | grep -o '0.0.0.0:[0-9]*' | cut -d: -f2 | head -1)
        
        if [ -n "$orch_port" ]; then
            echo "  Orchestrator API: http://localhost:$orch_port"
            echo "  Health Check: http://localhost:$orch_port/health"
            echo "  Status: http://localhost:$orch_port/status"
            echo "  MCP Endpoint: http://localhost:$orch_port/mcp"
            echo
            
            # Test orchestrator connectivity
            print_color $YELLOW "Connectivity Tests:"
            test_connectivity "localhost" "$orch_port" "Orchestrator"
        fi
    fi
}

# Main execution
main() {
    print_header
    
    # Check Docker availability
    check_docker
    
    # Show orchestrator containers
    print_color $YELLOW "=== MCP Orchestrator Containers ==="
    echo
    
    local orchestrator_output=$(get_orchestrator_container)
    if echo "$orchestrator_output" | grep -q "CONTAINER ID"; then
        echo "$orchestrator_output"
        echo
        
        # Show detailed info for each orchestrator container
        docker ps --filter "label=mcp.orchestrator=true" --format "{{.ID}} {{.Names}} {{.Image}} {{.Status}}" | while read -r id name image status; do
            if [ -n "$id" ]; then
                show_container_details "$id" "$name" "$image" "$status"
            fi
        done
    else
        print_color $RED "No orchestrator containers found"
        echo
    fi
    
    # Show agent containers
    print_color $YELLOW "=== MCP Agent Containers ==="
    echo
    
    local agent_output=$(get_mcp_containers)
    if echo "$agent_output" | grep -q "CONTAINER ID"; then
        echo "$agent_output"
        echo
        
        # Show detailed info for each agent container
        docker ps --filter "label=mcp.server=true" --format "{{.ID}} {{.Names}} {{.Image}} {{.Status}}" | while read -r id name image status; do
            if [ -n "$id" ]; then
                show_container_details "$id" "$name" "$image" "$status"
            fi
        done
    else
        print_color $RED "No MCP agent containers found"
        echo
    fi
    
    # Show summary
    show_summary
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Lists all MCP agent containers with their external ports"
        echo
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -q, --quiet    Show only summary"
        echo "  -v, --verbose  Show verbose output"
        echo
        exit 0
        ;;
    -q|--quiet)
        check_docker
        show_summary
        ;;
    -v|--verbose)
        set -x
        main
        ;;
    *)
        main
        ;;
esac
