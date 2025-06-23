#!/bin/bash

# MCP Multi-Agent Orchestrator - Comprehensive Health Check Script
# Verifies orchestrator and all agent containers are reachable and functional

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ORCHESTRATOR_URL="http://localhost:3000"
AGENTS=(
    "file-agent:http://localhost:3001"
    "memory-agent:http://localhost:3002"
    "intent-agent:http://localhost:3003"
    "task-agent:http://localhost:3004"
)

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print header
print_header() {
    echo
    print_color $BLUE "=== MCP Multi-Agent Orchestrator - Health Check ==="
    echo
    print_color $YELLOW "Checking orchestrator and all agent containers..."
    echo
}

# Function to check HTTP endpoint
check_endpoint() {
    local name=$1
    local url=$2
    local endpoint=$3
    local expected_status=${4:-200}
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    print_color $YELLOW "Checking $name ($url$endpoint)..."
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -w "%{http_code}" -o /tmp/health_response "$url$endpoint" 2>/dev/null || echo "000")
        
        if [ "$response" = "$expected_status" ]; then
            print_color $GREEN "  ✓ $name is healthy (HTTP $response)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            
            # Show response content if it's JSON
            if [ -f /tmp/health_response ]; then
                local content=$(cat /tmp/health_response 2>/dev/null)
                if echo "$content" | jq . >/dev/null 2>&1; then
                    echo "    Response: $(echo "$content" | jq -c .)"
                fi
            fi
            
            return 0
        else
            print_color $RED "  ✗ $name is unhealthy (HTTP $response)"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            
            # Show error response if available
            if [ -f /tmp/health_response ]; then
                local content=$(cat /tmp/health_response 2>/dev/null)
                if [ -n "$content" ]; then
                    echo "    Error: $content"
                fi
            fi
            
            return 1
        fi
    else
        print_color $RED "  ✗ curl not available, cannot check $name"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Function to check MCP functionality
check_mcp_functionality() {
    local name=$1
    local url=$2
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    print_color $YELLOW "Testing MCP functionality for $name..."
    
    # Test MCP ping
    local mcp_request='{"jsonrpc":"2.0","id":"health-check","method":"ping","params":{}}'
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$mcp_request" "$url/mcp" 2>/dev/null)
        
        if echo "$response" | jq -e '.result.pong' >/dev/null 2>&1; then
            print_color $GREEN "  ✓ $name MCP ping successful"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            print_color $RED "  ✗ $name MCP ping failed"
            echo "    Response: $response"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            return 1
        fi
    else
        print_color $RED "  ✗ curl not available, cannot test MCP for $name"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Function to check Docker containers
check_docker_containers() {
    print_color $YELLOW "Checking Docker containers..."
    
    if ! command -v docker >/dev/null 2>&1; then
        print_color $RED "  ✗ Docker not available"
        return 1
    fi
    
    # Check orchestrator container
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local orch_container=$(docker ps --filter "label=mcp.orchestrator=true" --format "{{.Names}}" 2>/dev/null | head -1)
    
    if [ -n "$orch_container" ]; then
        print_color $GREEN "  ✓ Orchestrator container running: $orch_container"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        print_color $RED "  ✗ Orchestrator container not found"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check agent containers
    local agent_containers=$(docker ps --filter "label=mcp.server=true" --format "{{.Names}}" 2>/dev/null)
    local agent_count=$(echo "$agent_containers" | wc -l)
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ "$agent_count" -ge 4 ]; then
        print_color $GREEN "  ✓ Found $agent_count agent containers:"
        echo "$agent_containers" | while read -r container; do
            if [ -n "$container" ]; then
                echo "    - $container"
            fi
        done
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        print_color $RED "  ✗ Expected 4 agent containers, found $agent_count"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Function to test orchestrator discovery
test_orchestrator_discovery() {
    print_color $YELLOW "Testing orchestrator agent discovery..."
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # Get orchestrator status
    local status_response=$(curl -s "$ORCHESTRATOR_URL/status" 2>/dev/null)
    
    if echo "$status_response" | jq -e '.orchestrator.agentCount' >/dev/null 2>&1; then
        local agent_count=$(echo "$status_response" | jq -r '.orchestrator.agentCount')
        local tool_count=$(echo "$status_response" | jq -r '.orchestrator.toolCount')
        
        print_color $GREEN "  ✓ Orchestrator discovered $agent_count agents with $tool_count tools"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Show discovered agents
        if echo "$status_response" | jq -e '.agents' >/dev/null 2>&1; then
            echo "    Discovered agents:"
            echo "$status_response" | jq -r '.agents[] | "    - \(.name) (\(.id))"' 2>/dev/null || true
        fi
        
    else
        print_color $RED "  ✗ Failed to get orchestrator status"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Function to test tool listing
test_tool_listing() {
    print_color $YELLOW "Testing tool listing through orchestrator..."
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # Test MCP tools/list
    local mcp_request='{"jsonrpc":"2.0","id":"health-check","method":"tools/list","params":{}}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$mcp_request" "$ORCHESTRATOR_URL/mcp" 2>/dev/null)
    
    if echo "$response" | jq -e '.result.tools' >/dev/null 2>&1; then
        local tool_count=$(echo "$response" | jq '.result.tools | length')
        print_color $GREEN "  ✓ Orchestrator lists $tool_count tools"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Show available tools
        echo "    Available tools:"
        echo "$response" | jq -r '.result.tools[] | "    - \(.name): \(.description)"' 2>/dev/null || true
        
    else
        print_color $RED "  ✗ Failed to list tools through orchestrator"
        echo "    Response: $response"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Function to show summary
show_summary() {
    echo
    print_color $BLUE "=== Health Check Summary ==="
    echo
    
    print_color $GREEN "Passed: $PASSED_CHECKS/$TOTAL_CHECKS"
    print_color $RED "Failed: $FAILED_CHECKS/$TOTAL_CHECKS"
    
    local success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo "Success Rate: $success_rate%"
    
    echo
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        print_color $GREEN "🎉 All health checks passed! System is fully operational."
        echo
        print_color $BLUE "System Endpoints:"
        echo "  Orchestrator: $ORCHESTRATOR_URL"
        echo "  Health Check: $ORCHESTRATOR_URL/health"
        echo "  Status: $ORCHESTRATOR_URL/status"
        echo "  MCP Endpoint: $ORCHESTRATOR_URL/mcp"
        echo
        for agent_info in "${AGENTS[@]}"; do
            IFS=':' read -r agent_name agent_url <<< "$agent_info"
            echo "  $agent_name: $agent_url"
        done
        
        return 0
    else
        print_color $RED "❌ Some health checks failed. Please review the issues above."
        echo
        print_color $YELLOW "Troubleshooting tips:"
        echo "  1. Ensure all containers are running: docker ps"
        echo "  2. Check container logs: docker logs <container-name>"
        echo "  3. Verify network connectivity between containers"
        echo "  4. Check if ports are properly exposed"
        echo
        return 1
    fi
}

# Main execution
main() {
    print_header
    
    # Check Docker containers first
    check_docker_containers
    echo
    
    # Check orchestrator health
    check_endpoint "Orchestrator" "$ORCHESTRATOR_URL" "/health"
    check_mcp_functionality "Orchestrator" "$ORCHESTRATOR_URL"
    echo
    
    # Check all agent endpoints
    for agent_info in "${AGENTS[@]}"; do
        IFS=':' read -r agent_name agent_url <<< "$agent_info"
        check_endpoint "$agent_name" "$agent_url" "/health"
        check_mcp_functionality "$agent_name" "$agent_url"
        echo
    done
    
    # Test orchestrator functionality
    test_orchestrator_discovery
    echo
    
    test_tool_listing
    echo
    
    # Show summary
    show_summary
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Comprehensive health check for MCP Multi-Agent Orchestrator"
        echo
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -q, --quiet    Minimal output (summary only)"
        echo "  -v, --verbose  Verbose output with detailed responses"
        echo
        exit 0
        ;;
    -q|--quiet)
        # Run checks but only show summary
        main >/dev/null 2>&1
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
