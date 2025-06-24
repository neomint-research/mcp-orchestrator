# MCP Orchestrator System Overview

This document provides a high-level architecture overview of the MCP Multi-Agent Orchestrator, showing component relationships, data flow, and integration points with emphasis on Docker rootless architecture support.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MCP Orchestrator System                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐ │
│  │   HTTP Client   │    │         Core Orchestrator           │ │
│  │   (Port 3000)   │◄──►│      (src/core/backend/)           │ │
│  └─────────────────┘    │                                     │ │
│                         │  ┌─────────────┐ ┌─────────────┐    │ │
│                         │  │ Discovery   │ │ Router      │    │ │
│                         │  │ (Docker)    │ │ (Tools)     │    │ │
│                         │  └─────────────┘ └─────────────┘    │ │
│                         │                                     │ │
│                         │  ┌─────────────┐ ┌─────────────┐    │ │
│                         │  │ Validator   │ │ Hardening   │    │ │
│                         │  │ (Schema)    │ │ (Security)  │    │ │
│                         │  └─────────────┘ └─────────────┘    │ │
│                         │                                     │ │
│                         │  ┌─────────────────────────────────┐ │ │
│                         │  │        Registry Manager        │ │ │
│                         │  │     (Plugin Management)        │ │ │
│                         │  └─────────────────────────────────┘ │ │
│                         └─────────────────────────────────────┘ │
│                                           │                     │
│                                           ▼                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                Docker Infrastructure                        │ │
│  │                                                             │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────┐ │ │
│  │  │File Agent   │ │Memory Agent │ │Intent Agent │ │Task    │ │ │
│  │  │(Port 3001)  │ │(Port 3002)  │ │(Port 3003)  │ │Agent   │ │ │
│  │  │             │ │             │ │             │ │(3004)  │ │ │
│  │  │File Ops     │ │Knowledge    │ │NLU/Intent   │ │Project │ │ │
│  │  │- read_file  │ │- store      │ │- analyze    │ │Mgmt    │ │ │
│  │  │- write_file │ │- query      │ │- extract    │ │- create│ │ │
│  │  │- list_dir   │ │- relate     │ │- suggest    │ │- track │ │ │
│  │  │- create_dir │ │- context    │ │- disambig   │ │- status│ │ │
│  │  │- delete     │ │             │ │             │ │        │ │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                           │                     │
│                                           ▼                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Docker Socket Layer                            │ │
│  │                                                             │ │
│  │  Rootless Mode:     /run/user/{uid}/docker.sock            │ │
│  │  Alternative:      /tmp/docker-{uid}/docker.sock          │ │
│  │  Socket Detection: Dynamic user-specific path resolution  │ │
│  │  Security Focus:   No root privileges or docker group     │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Component Relationships

### Core Orchestrator Components

#### Discovery ↔ Registry
- **Discovery** finds agents via Docker labels and registers them with **Registry**
- **Registry** maintains persistent agent metadata and status
- Bidirectional communication for agent lifecycle management

#### Router ↔ Registry  
- **Router** queries **Registry** for available agents and tools
- **Registry** provides agent health status for routing decisions
- Load balancing and failover coordination

#### Validator ↔ Hardening
- **Validator** performs schema validation before **Hardening** security checks
- **Hardening** applies security policies after **Validator** confirms structure
- Layered security approach with clear separation of concerns

#### Orchestrator ↔ All Components
- **Orchestrator** coordinates all core components
- Provides unified MCP interface while delegating to specialized components
- Manages component lifecycle and error handling

### Agent Module Integration

#### Agent Discovery Flow
1. **Docker Labels**: Agents expose MCP metadata via container labels
2. **Discovery Service**: Scans Docker containers for MCP agents
3. **Registry Registration**: Discovered agents registered with metadata
4. **Tool Aggregation**: Agent tools collected and validated
5. **Router Configuration**: Routing rules updated for new agents

#### Tool Call Flow
1. **HTTP Request**: Client sends MCP JSON-RPC request to orchestrator
2. **Validation**: Request validated against MCP protocol schema
3. **Security Check**: Hardening component applies security policies
4. **Tool Resolution**: Router identifies target agent for tool
5. **Agent Communication**: HTTP request forwarded to agent container
6. **Response Processing**: Agent response validated and returned

## Data Flow Architecture

### Request Processing Pipeline

```
Client Request → Orchestrator → Validator → Hardening → Router → Agent
     ↓              ↓             ↓           ↓          ↓        ↓
HTTP/JSON-RPC → Parse/Route → Schema Check → Security → Route → Execute
     ↑              ↑             ↑           ↑          ↑        ↑
Client Response ← Orchestrator ← Validator ← Hardening ← Router ← Agent
```

### Agent Discovery Pipeline

```
Docker Containers → Discovery → Registry → Router → Orchestrator
        ↓              ↓          ↓         ↓          ↓
   Label Scanning → Agent Info → Storage → Routes → Tool List
```

## Docker Rootless Integration

### Socket Detection Strategy
1. **Environment Check**: Verify `DOCKER_MODE=rootless` configuration
2. **UID Detection**: Get current user ID for user-specific socket path
3. **Socket Availability**: Test rootless socket accessibility and permissions
4. **Path Resolution**: Try multiple rootless socket locations
5. **Security Validation**: Ensure no fallback to privileged sockets

### Permission Model
- **Rootless Mode**: User namespace isolation, no root privileges required
- **Security-First**: No fallback to standard Docker or privileged access
- **User Isolation**: Containers run with user privileges only
- **Socket Access**: Read-only access to user-specific Docker sockets

### Configuration Management
- **Environment Variables**: Mode-specific configuration in `.env` files
- **Docker Compose**: Separate compose files for rootless and standard modes
- **Volume Mounting**: Dynamic socket path mounting based on detected mode
- **User Mapping**: Proper UID/GID mapping for rootless containers

## Integration Points

### External Integrations
- **Docker API**: Container discovery and management
- **File System**: Agent storage and configuration
- **Network**: HTTP-based inter-agent communication
- **Process Management**: Container lifecycle and health monitoring

### Internal Integrations
- **MCP Protocol**: Standardized tool interface across all agents
- **JSON-RPC**: Communication protocol for all interactions
- **Docker Labels**: Metadata-driven agent discovery
- **Health Checks**: Continuous agent availability monitoring

### Test Integration
- **Unit Tests**: Individual component validation
- **Integration Tests**: Cross-component interaction testing
- **E2E Tests**: Complete workflow validation
- **Docker Tests**: Rootless and standard mode compatibility
- **Resilience Tests**: Failure scenarios and recovery testing

## Deployment Architecture

### Container Organization
- **Core Container**: Single orchestrator container with all core components
- **Agent Containers**: Separate containers for each agent module
- **Shared Volumes**: Registry and temp data persistence
- **Network**: Docker bridge network for inter-container communication

### Deployment Modes

#### Rootless Docker Deployment (Security-First)
```bash
# Prerequisites: Rootless Docker, Docker Compose, Node.js 18+
./setup.ps1
# Uses: docker-compose.yml (rootless-only configuration)
# Socket: /run/user/{uid}/docker.sock
# User: No root privileges or docker group membership required
```

#### Rootless Docker Deployment (Recommended)
```bash
# Prerequisites: Rootless Docker installation
curl -fsSL https://get.docker.com/rootless | sh
export PATH=/home/$USER/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
systemctl --user enable docker
systemctl --user start docker
sudo loginctl enable-linger $USER

# Deploy orchestrator
./scripts/deploy/start-rootless.sh -d
# Uses: docker-compose.yml (Unix/Linux) or docker-compose.windows.yml (Windows)
# Socket: /run/user/{uid}/docker.sock (Unix) or //./pipe/docker_engine (Windows)
# User: No privileged access required
```

#### Deployment Verification
```bash
# Check container status
docker ps

# Test orchestrator health
curl http://localhost:3000/health

# Verify agent discovery
curl http://localhost:3000/agents

# Test individual agents
curl http://localhost:3001/health  # File agent
curl http://localhost:3002/health  # Memory agent
curl http://localhost:3003/health  # Intent agent
curl http://localhost:3004/health  # Task agent
```

### Scaling Considerations
- **Horizontal Scaling**: Multiple agent instances for load distribution
- **Vertical Scaling**: Resource allocation per container
- **Load Balancing**: Router-based request distribution
- **Health Monitoring**: Automatic failover and recovery

### Security Architecture
- **Container Isolation**: Each agent runs in isolated container
- **Network Segmentation**: Controlled inter-container communication
- **Rootless Support**: Enhanced security through user namespace isolation
- **Read-Only Mounts**: Minimal write access for security
- **Non-Root Users**: All containers run as non-privileged users

## Performance Characteristics

### Latency Profile
- **Tool Discovery**: ~100ms for initial agent discovery
- **Tool Routing**: ~10ms for tool call routing
- **Agent Communication**: ~50ms for inter-container HTTP calls
- **Total Request**: ~200ms for typical tool call end-to-end

### Throughput Capacity
- **Concurrent Requests**: 100+ simultaneous tool calls
- **Agent Capacity**: 10+ agent containers per orchestrator
- **Discovery Rate**: 1000+ containers scanned per discovery cycle
- **Tool Aggregation**: 100+ tools managed per agent

### Resource Utilization
- **Memory**: ~50MB per core container, ~20MB per agent
- **CPU**: Low baseline usage, scales with request volume
- **Network**: Minimal overhead for JSON-RPC communication
- **Storage**: Persistent registry and temp data, minimal footprint

## Operational Procedures

### Rootless Docker Operations

#### Service Management
```bash
# Start services
./scripts/deploy/start-rootless.sh -d

# Stop services
docker-compose down

# Restart services
docker-compose restart

# View logs
docker-compose logs -f

# Check service status
systemctl --user status docker
```

#### Monitoring and Diagnostics
```bash
# Monitor container resources
docker stats

# Check orchestrator logs
docker logs mcp-orchestrator-core

# Monitor Docker daemon
journalctl --user -u docker -f

# Quick diagnostic check
echo "User: $(whoami) (UID: $(id -u))"
echo "Docker Host: ${DOCKER_HOST:-not set}"
echo "Socket Path: /run/user/$(id -u)/docker.sock"
echo "Socket Exists: $(test -S /run/user/$(id -u)/docker.sock && echo 'YES' || echo 'NO')"
echo "Docker Service: $(systemctl --user is-active docker 2>/dev/null || echo 'inactive')"
```

#### Maintenance Tasks
```bash
# Update containers
docker-compose pull
docker-compose up -d

# Clean up unused resources
docker system prune -f

# Backup registry data
docker run --rm -v mcp-orchestrator_registry-data:/data -v $(pwd):/backup alpine tar czf /backup/registry-backup.tar.gz -C /data .

# Restore registry data
docker run --rm -v mcp-orchestrator_registry-data:/data -v $(pwd):/backup alpine tar xzf /backup/registry-backup.tar.gz -C /data
```

### Testing and Validation

#### Test Suites
```bash
# Run rootless-specific tests
./scripts/testing/test-rootless.sh

# Run comprehensive test suite
npm run test:all

# Run Docker configuration tests
npm run test:docker
```

#### Health Checks
```bash
# Comprehensive health check
./scripts/core/health-check-all.sh

# Test MCP server functionality
./scripts/testing/test-mcp-server.sh

# Validate rootless end-to-end
./scripts/testing/validate-rootless-e2e.sh
```

This architecture provides a robust, scalable, and secure foundation for MCP tool orchestration with first-class Docker rootless support.
