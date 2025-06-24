#!/bin/bash

# MCP Multi-Agent Orchestrator - Agent Generator Script
# Generates complete NEOMINT-compliant module structure for new agents
# Moved to scripts/modules/ for better organization per NEOMINT-RESEARCH guidelines

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
    print_color $BLUE "=== MCP Agent Generator ==="
    echo
    print_color $YELLOW "Generating NEOMINT-compliant MCP agent module..."
    echo
}

# Function to validate agent name
validate_agent_name() {
    local name=$1
    
    if [ -z "$name" ]; then
        print_color $RED "Error: Agent name is required"
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        print_color $RED "Error: Agent name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens"
        return 1
    fi
    
    if [ -d "src/modules/$name" ]; then
        print_color $RED "Error: Agent '$name' already exists"
        return 1
    fi
    
    return 0
}

# Function to get next available port
get_next_port() {
    local base_port=3005
    local max_port=3099
    
    for ((port=base_port; port<=max_port; port++)); do
        if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo $port
            return 0
        fi
    done
    
    # Fallback to a high port if all are taken
    echo $((3000 + RANDOM % 1000))
}

# Function to create directory structure
create_directory_structure() {
    local agent_name=$1
    
    print_color $YELLOW "Creating directory structure..."
    
    # Create module directories
    mkdir -p "src/modules/$agent_name/backend"
    mkdir -p "environments/modules/$agent_name"
    
    print_color $GREEN "✓ Created directory structure"
}

# Function to create plugin.json
create_plugin_json() {
    local agent_name=$1
    local description=$2
    local port=$3
    local tools=$4
    
    print_color $YELLOW "Creating plugin.json..."
    
    # Parse tools into JSON format
    local tools_json=""
    if [ -n "$tools" ]; then
        IFS=',' read -ra TOOL_ARRAY <<< "$tools"
        local tool_objects=()
        
        for tool in "${TOOL_ARRAY[@]}"; do
            tool=$(echo "$tool" | xargs) # trim whitespace
            tool_objects+=("\"$tool\": {
          \"description\": \"$tool functionality for $agent_name\",
          \"inputSchema\": {
            \"type\": \"object\",
            \"properties\": {
              \"input\": {
                \"type\": \"string\",
                \"description\": \"Input for $tool\"
              }
            },
            \"required\": [\"input\"]
          }
        }")
        done
        
        tools_json=$(IFS=','; echo "${tool_objects[*]}")
    fi
    
    cat > "src/modules/$agent_name/plugin.json" << EOF
{
  "name": "$agent_name",
  "version": "1.0.0",
  "description": "$description",
  "type": "mcp-server",
  "author": "NEOMINT Research",
  "license": "MIT",
  "main": "backend/index.js",
  "mcp": {
    "server": {
      "name": "$agent_name",
      "version": "1.0.0",
      "protocol": "http",
      "port": $port,
      "endpoints": {
        "initialize": "/mcp",
        "tools": "/mcp",
        "health": "/health"
      }
    },
    "capabilities": {
      "tools": {
        $tools_json
      }
    }
  },
  "docker": {
    "labels": {
      "mcp.server": "true",
      "mcp.server.name": "$agent_name",
      "mcp.server.port": "$port",
      "mcp.server.protocol": "http"
    }
  },
  "keywords": [
    "mcp",
    "$agent_name",
    "agent",
    "neomint"
  ]
}
EOF
    
    print_color $GREEN "✓ Created plugin.json"
}

# Function to create backend implementation
create_backend_implementation() {
    local agent_name=$1
    local port=$2
    local tools=$3
    
    print_color $YELLOW "Creating backend implementation..."
    
    # Create main server file
    cat > "src/modules/$agent_name/backend/index.js" << 'EOF'
#!/usr/bin/env node

/**
 * MCP AGENT_NAME Agent - Backend Implementation
 * 
 * Provides AGENT_DESCRIPTION through MCP protocol
 */

const http = require('http');

class AGENT_CLASS_NAMEServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.AGENT_NAME_UPPER_PORT || AGENT_PORT,
            host: config.host || process.env.AGENT_NAME_UPPER_HOST || '0.0.0.0',
            ...config
        };
        
        this.server = null;
        this.initialized = false;
    }
    
    async start() {
        this.server = http.createServer((req, res) => this.handleRequest(req, res));
        await new Promise((resolve, reject) => {
            this.server.listen(this.config.port, this.config.host, (error) => {
                if (error) reject(error);
                else resolve();
            });
        });
        console.log(`AGENT_NAME Agent Server started on ${this.config.host}:${this.config.port}`);
    }
    
    async handleRequest(req, res) {
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        
        if (req.method === 'OPTIONS') {
            res.writeHead(200);
            res.end();
            return;
        }
        
        const url = new URL(req.url, `http://${req.headers.host}`);
        
        if (url.pathname === '/health') {
            this.sendJSON(res, 200, { 
                status: 'healthy', 
                timestamp: new Date().toISOString(),
                agent: 'AGENT_NAME',
                initialized: this.initialized
            });
        } else if (url.pathname === '/mcp') {
            await this.handleMCPRequest(req, res);
        } else {
            this.sendJSON(res, 404, { error: 'Not Found' });
        }
    }
    
    async handleMCPRequest(req, res) {
        if (req.method !== 'POST') {
            this.sendJSON(res, 405, { error: 'Method Not Allowed' });
            return;
        }
        
        const body = await this.readRequestBody(req);
        const jsonRequest = JSON.parse(body);
        
        let result;
        switch (jsonRequest.method) {
            case 'initialize':
                this.initialized = true;
                result = { 
                    protocolVersion: "2024-11-05", 
                    capabilities: { tools: {} }, 
                    serverInfo: { name: "AGENT_NAME", version: "1.0.0" } 
                };
                break;
            case 'tools/list':
                result = { tools: TOOLS_ARRAY };
                break;
            case 'tools/call':
                result = await this.handleToolCall(jsonRequest.params);
                break;
            case 'ping':
                result = { pong: true, timestamp: new Date().toISOString(), agent: 'AGENT_NAME' };
                break;
            default:
                this.sendJSONRPCError(res, jsonRequest.id, -32601, 'Method not found');
                return;
        }
        
        this.sendJSONRPCSuccess(res, jsonRequest.id, result);
    }
    
    async handleToolCall(params) {
        const { name: toolName, arguments: toolArgs } = params;
        
        switch (toolName) {
TOOL_CASES
            default:
                throw new Error(`Unknown tool: ${toolName}`);
        }
    }
    
    readRequestBody(req) {
        return new Promise((resolve, reject) => {
            let body = '';
            req.on('data', (chunk) => { body += chunk.toString(); });
            req.on('end', () => { resolve(body); });
            req.on('error', (error) => { reject(error); });
        });
    }
    
    sendJSONRPCSuccess(res, id, result) {
        this.sendJSON(res, 200, { jsonrpc: '2.0', id: id, result: result });
    }
    
    sendJSONRPCError(res, id, code, message) {
        this.sendJSON(res, 200, { jsonrpc: '2.0', id: id, error: { code: code, message: message } });
    }
    
    sendJSON(res, statusCode, data) {
        res.writeHead(statusCode, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data, null, 2));
    }
}

if (require.main === module) {
    const server = new AGENT_CLASS_NAMEServer();
    server.start().catch(console.error);
}

module.exports = { AGENT_CLASS_NAMEServer };
EOF
    
    # Replace placeholders
    local agent_name_upper=$(echo "$agent_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    local agent_class_name=$(echo "$agent_name" | sed 's/-/ /g' | sed 's/\b\w/\U&/g' | sed 's/ //g')
    
    # Generate tools array and cases
    local tools_array="[]"
    local tool_cases=""
    
    if [ -n "$tools" ]; then
        IFS=',' read -ra TOOL_ARRAY <<< "$tools"
        local tool_objects=()
        local case_statements=()
        
        for tool in "${TOOL_ARRAY[@]}"; do
            tool=$(echo "$tool" | xargs) # trim whitespace
            tool_objects+=("{ name: \"$tool\", description: \"$tool functionality\", inputSchema: { type: \"object\", properties: { input: { type: \"string\" } }, required: [\"input\"] } }")
            case_statements+=("            case '$tool':")
            case_statements+=("                return { tool: '$tool', input: toolArgs.input || '', result: 'success', timestamp: new Date().toISOString() };")
        done
        
        tools_array="[$(IFS=','; echo "${tool_objects[*]}")]"
        tool_cases=$(printf "%s\n" "${case_statements[@]}")
    fi
    
    sed -i "s/AGENT_NAME/$agent_name/g" "src/modules/$agent_name/backend/index.js"
    sed -i "s/AGENT_NAME_UPPER/$agent_name_upper/g" "src/modules/$agent_name/backend/index.js"
    sed -i "s/AGENT_CLASS_NAME/$agent_class_name/g" "src/modules/$agent_name/backend/index.js"
    sed -i "s/AGENT_PORT/$port/g" "src/modules/$agent_name/backend/index.js"
    sed -i "s|TOOLS_ARRAY|$tools_array|g" "src/modules/$agent_name/backend/index.js"
    sed -i "s|TOOL_CASES|$tool_cases|g" "src/modules/$agent_name/backend/index.js"
    
    print_color $GREEN "✓ Created backend implementation"
}

# Function to create Dockerfile
create_dockerfile() {
    local agent_name=$1
    local port=$2
    
    print_color $YELLOW "Creating Dockerfile..."
    
    cat > "environments/modules/$agent_name/Dockerfile" << EOF
# MCP $agent_name Agent Container
FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache curl bash
RUN addgroup -g 1001 -S mcpuser && adduser -S mcpuser -u 1001 -G mcpuser

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY src/modules/$agent_name/ ./src/modules/$agent_name/

RUN chown -R mcpuser:mcpuser /app

USER mcpuser

EXPOSE $port

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:$port/health || exit 1

ENV NODE_ENV=production
ENV ${agent_name^^}_AGENT_PORT=$port
ENV ${agent_name^^}_AGENT_HOST=0.0.0.0

LABEL mcp.server=true
LABEL mcp.server.name=$agent_name
LABEL mcp.server.port=$port
LABEL mcp.server.protocol=http

CMD ["node", "src/modules/$agent_name/backend/index.js"]
EOF
    
    print_color $GREEN "✓ Created Dockerfile"
}

# Function to update docker-compose.yml
update_docker_compose() {
    local agent_name=$1
    local port=$2
    
    print_color $YELLOW "Updating docker-compose.yml..."
    
    # Add service to docker-compose.yml
    cat >> "deploy/docker-compose.yml" << EOF

  $agent_name:
    build:
      context: ..
      dockerfile: environments/modules/$agent_name/Dockerfile
    container_name: mcp-$agent_name
    ports:
      - "$port:$port"
    environment:
      - NODE_ENV=production
      - ${agent_name^^}_AGENT_PORT=$port
      - ${agent_name^^}_AGENT_HOST=0.0.0.0
    networks:
      - mcp-network
    restart: unless-stopped
    labels:
      - "mcp.server=true"
      - "mcp.server.name=$agent_name"
      - "mcp.server.port=$port"
      - "mcp.server.protocol=http"
EOF
    
    print_color $GREEN "✓ Updated docker-compose.yml"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <agent-name> [options]"
    echo
    echo "Generate a new MCP agent module with NEOMINT-compliant structure"
    echo
    echo "Arguments:"
    echo "  agent-name     Name of the agent (lowercase, hyphens allowed)"
    echo
    echo "Options:"
    echo "  -d, --description DESC    Agent description"
    echo "  -p, --port PORT          Port number (auto-assigned if not specified)"
    echo "  -t, --tools TOOLS        Comma-separated list of tool names"
    echo "  -h, --help               Show this help message"
    echo
    echo "Examples:"
    echo "  $0 weather-agent -d \"Weather information agent\" -t \"get_weather,get_forecast\""
    echo "  $0 database-agent -p 3010 -t \"query_db,insert_record,update_record\""
    echo
}

# Main execution
main() {
    local agent_name=""
    local description=""
    local port=""
    local tools=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--description)
                description="$2"
                shift 2
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            -t|--tools)
                tools="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_color $RED "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$agent_name" ]; then
                    agent_name="$1"
                else
                    print_color $RED "Multiple agent names specified"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$agent_name" ]; then
        print_color $RED "Error: Agent name is required"
        show_usage
        exit 1
    fi
    
    # Validate agent name
    if ! validate_agent_name "$agent_name"; then
        exit 1
    fi
    
    # Set defaults
    if [ -z "$description" ]; then
        description="MCP $agent_name agent providing specialized functionality"
    fi
    
    if [ -z "$port" ]; then
        port=$(get_next_port)
    fi
    
    print_header
    
    print_color $BLUE "Agent Configuration:"
    echo "  Name: $agent_name"
    echo "  Description: $description"
    echo "  Port: $port"
    echo "  Tools: ${tools:-"none"}"
    echo
    
    # Create agent structure
    create_directory_structure "$agent_name"
    create_plugin_json "$agent_name" "$description" "$port" "$tools"
    create_backend_implementation "$agent_name" "$port" "$tools"
    create_dockerfile "$agent_name" "$port"
    update_docker_compose "$agent_name" "$port"
    
    echo
    print_color $GREEN "🎉 Agent '$agent_name' created successfully!"
    echo
    print_color $BLUE "Next steps:"
    echo "  1. Customize the implementation in src/modules/$agent_name/backend/index.js"
    echo "  2. Build and test: docker-compose up --build $agent_name"
    echo "  3. Test the agent: scripts/test-mcp-server.sh -a $agent_name"
    echo "  4. Add to orchestrator discovery by restarting the system"
    echo
}

# Run main function
main "$@"
