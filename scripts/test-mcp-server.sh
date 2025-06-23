#!/bin/bash

# MCP Multi-Agent Orchestrator - MCP Server Testing Script
# Tests direct MCP connections to each agent and validates tool functionality

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
    "orchestrator:$ORCHESTRATOR_URL"
    "file-agent:http://localhost:3001"
    "memory-agent:http://localhost:3002"
    "intent-agent:http://localhost:3003"
    "task-agent:http://localhost:3004"
)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print header
print_header() {
    echo
    print_color $BLUE "=== MCP Multi-Agent Orchestrator - MCP Server Testing ==="
    echo
    print_color $YELLOW "Testing direct MCP connections and tool functionality..."
    echo
}

# Function to send MCP request
send_mcp_request() {
    local url=$1
    local request=$2
    local description=$3
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    print_color $YELLOW "  Testing: $description"
    
    if ! command -v curl >/dev/null 2>&1; then
        print_color $RED "    ✗ curl not available"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$request" "$url/mcp" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        print_color $RED "    ✗ Request failed or no response"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        print_color $RED "    ✗ Invalid JSON response"
        echo "    Response: $response"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check for JSON-RPC error
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_code=$(echo "$response" | jq -r '.error.code')
        local error_message=$(echo "$response" | jq -r '.error.message')
        print_color $RED "    ✗ MCP Error $error_code: $error_message"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check for result
    if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        print_color $GREEN "    ✓ Success"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        # Show result summary if verbose
        if [ "${VERBOSE:-false}" = "true" ]; then
            echo "    Result: $(echo "$response" | jq -c '.result')"
        fi
        
        return 0
    else
        print_color $RED "    ✗ No result in response"
        echo "    Response: $response"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to test MCP initialize
test_initialize() {
    local name=$1
    local url=$2
    
    local request='{
        "jsonrpc": "2.0",
        "id": "test-init",
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "clientInfo": {
                "name": "mcp-test-client",
                "version": "1.0.0"
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "Initialize $name"
}

# Function to test tools/list
test_tools_list() {
    local name=$1
    local url=$2
    
    local request='{
        "jsonrpc": "2.0",
        "id": "test-tools-list",
        "method": "tools/list",
        "params": {}
    }'
    
    if send_mcp_request "$url" "$request" "List tools for $name"; then
        # Show tool count
        local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$request" "$url/mcp" 2>/dev/null)
        local tool_count=$(echo "$response" | jq '.result.tools | length' 2>/dev/null || echo "0")
        echo "    Tools available: $tool_count"
        
        if [ "${VERBOSE:-false}" = "true" ]; then
            echo "$response" | jq -r '.result.tools[] | "      - \(.name): \(.description)"' 2>/dev/null || true
        fi
    fi
}

# Function to test ping
test_ping() {
    local name=$1
    local url=$2
    
    local request='{
        "jsonrpc": "2.0",
        "id": "test-ping",
        "method": "ping",
        "params": {}
    }'
    
    send_mcp_request "$url" "$request" "Ping $name"
}

# Function to test specific tools
test_file_agent_tools() {
    local url=$1
    
    print_color $BLUE "  Testing File Agent Tools:"
    
    # Test list_directory
    local request='{
        "jsonrpc": "2.0",
        "id": "test-list-dir",
        "method": "tools/call",
        "params": {
            "name": "list_directory",
            "arguments": {
                "path": "/app/workspace"
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "list_directory tool"
    
    # Test create_directory
    local request='{
        "jsonrpc": "2.0",
        "id": "test-create-dir",
        "method": "tools/call",
        "params": {
            "name": "create_directory",
            "arguments": {
                "path": "/app/workspace/test-dir",
                "recursive": true
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "create_directory tool"
    
    # Test write_file
    local request='{
        "jsonrpc": "2.0",
        "id": "test-write-file",
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "path": "/app/workspace/test-file.txt",
                "content": "Hello from MCP test!",
                "createDirectories": true
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "write_file tool"
    
    # Test read_file
    local request='{
        "jsonrpc": "2.0",
        "id": "test-read-file",
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "path": "/app/workspace/test-file.txt"
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "read_file tool"
}

# Function to test memory agent tools
test_memory_agent_tools() {
    local url=$1
    
    print_color $BLUE "  Testing Memory Agent Tools:"
    
    # Test store_knowledge
    local request='{
        "jsonrpc": "2.0",
        "id": "test-store-knowledge",
        "method": "tools/call",
        "params": {
            "name": "store_knowledge",
            "arguments": {
                "key": "test-knowledge",
                "content": "This is a test knowledge item for MCP testing",
                "metadata": {
                    "type": "test",
                    "category": "mcp-testing"
                }
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "store_knowledge tool"
    
    # Test query_knowledge
    local request='{
        "jsonrpc": "2.0",
        "id": "test-query-knowledge",
        "method": "tools/call",
        "params": {
            "name": "query_knowledge",
            "arguments": {
                "query": "test",
                "type": "fuzzy",
                "limit": 5
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "query_knowledge tool"
}

# Function to test intent agent tools
test_intent_agent_tools() {
    local url=$1
    
    print_color $BLUE "  Testing Intent Agent Tools:"
    
    # Test analyze_intent
    local request='{
        "jsonrpc": "2.0",
        "id": "test-analyze-intent",
        "method": "tools/call",
        "params": {
            "name": "analyze_intent",
            "arguments": {
                "text": "I want to read a file from the system"
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "analyze_intent tool"
    
    # Test extract_entities
    local request='{
        "jsonrpc": "2.0",
        "id": "test-extract-entities",
        "method": "tools/call",
        "params": {
            "name": "extract_entities",
            "arguments": {
                "text": "Please create a new project called MyProject in the documents folder"
            }
        }
    }'
    
    send_mcp_request "$url" "$request" "extract_entities tool"
}

# Function to test task agent tools
test_task_agent_tools() {
    local url=$1
    
    print_color $BLUE "  Testing Task Agent Tools:"
    
    # Test create_project
    local request='{
        "jsonrpc": "2.0",
        "id": "test-create-project",
        "method": "tools/call",
        "params": {
            "name": "create_project",
            "arguments": {
                "name": "Test Project",
                "description": "A test project for MCP validation"
            }
        }
    }'
    
    if send_mcp_request "$url" "$request" "create_project tool"; then
        # Get project ID from response for subsequent tests
        local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$request" "$url/mcp" 2>/dev/null)
        local project_id=$(echo "$response" | jq -r '.result.projectId' 2>/dev/null)
        
        if [ -n "$project_id" ] && [ "$project_id" != "null" ]; then
            # Test get_project_status
            local status_request='{
                "jsonrpc": "2.0",
                "id": "test-project-status",
                "method": "tools/call",
                "params": {
                    "name": "get_project_status",
                    "arguments": {
                        "projectId": "'$project_id'"
                    }
                }
            }'
            
            send_mcp_request "$url" "$status_request" "get_project_status tool"
        fi
    fi
}

# Function to test agent
test_agent() {
    local agent_info=$1
    IFS=':' read -r agent_name agent_url <<< "$agent_info"
    
    print_color $BLUE "Testing $agent_name ($agent_url):"
    
    # Basic MCP protocol tests
    test_initialize "$agent_name" "$agent_url"
    test_tools_list "$agent_name" "$agent_url"
    test_ping "$agent_name" "$agent_url"
    
    # Agent-specific tool tests
    case "$agent_name" in
        "file-agent")
            test_file_agent_tools "$agent_url"
            ;;
        "memory-agent")
            test_memory_agent_tools "$agent_url"
            ;;
        "intent-agent")
            test_intent_agent_tools "$agent_url"
            ;;
        "task-agent")
            test_task_agent_tools "$agent_url"
            ;;
        "orchestrator")
            # Orchestrator has all tools, test a few key ones
            print_color $BLUE "  Testing Orchestrator Tool Routing:"
            test_file_agent_tools "$agent_url"
            ;;
    esac
    
    echo
}

# Function to show summary
show_summary() {
    echo
    print_color $BLUE "=== MCP Testing Summary ==="
    echo
    
    print_color $GREEN "Passed: $PASSED_TESTS/$TOTAL_TESTS"
    print_color $RED "Failed: $FAILED_TESTS/$TOTAL_TESTS"
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Success Rate: $success_rate%"
    
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_color $GREEN "🎉 All MCP tests passed! All agents are functioning correctly."
        return 0
    else
        print_color $RED "❌ Some MCP tests failed. Please review the issues above."
        return 1
    fi
}

# Main execution
main() {
    print_header
    
    # Test each agent
    for agent_info in "${AGENTS[@]}"; do
        test_agent "$agent_info"
    done
    
    # Show summary
    show_summary
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Test MCP server functionality for all agents"
        echo
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -v, --verbose  Show detailed responses"
        echo "  -a, --agent    Test specific agent (orchestrator|file-agent|memory-agent|intent-agent|task-agent)"
        echo
        exit 0
        ;;
    -v|--verbose)
        export VERBOSE=true
        main
        ;;
    -a|--agent)
        if [ -z "$2" ]; then
            echo "Error: Agent name required"
            exit 1
        fi
        
        # Find and test specific agent
        for agent_info in "${AGENTS[@]}"; do
            IFS=':' read -r agent_name agent_url <<< "$agent_info"
            if [ "$agent_name" = "$2" ]; then
                print_header
                test_agent "$agent_info"
                show_summary
                exit $?
            fi
        done
        
        echo "Error: Unknown agent '$2'"
        echo "Available agents: orchestrator, file-agent, memory-agent, intent-agent, task-agent"
        exit 1
        ;;
    *)
        main
        ;;
esac
