# MCP Orchestrator Core System

This document provides detailed technical documentation for the core MCP orchestrator system components and their integration with Docker rootless architecture.

## Core Architecture

The MCP Orchestrator core system is built around a modular architecture that enables dynamic agent discovery, intelligent tool routing, and robust error handling while maintaining full compatibility with Docker rootless environments.

### Core Components

#### 1. Orchestrator (`src/core/backend/orchestrator.js`)
**Purpose**: Main MCP server interface and coordination hub
**Key Responsibilities**:
- Implements MCP JSON-RPC protocol endpoints (initialize, tools/list, tools/call)
- Coordinates between discovery, routing, validation, and hardening components
- Manages agent lifecycle and tool aggregation
- Provides unified API surface for all MCP operations

**Rootless Docker Integration**:
- Exclusively uses rootless Docker for enhanced security
- Dynamic socket path detection for user-specific Docker instances
- No fallback to standard Docker - security-first approach

#### 2. Discovery (`src/core/backend/discovery.js`)
**Purpose**: Docker-based agent discovery and monitoring
**Key Responsibilities**:
- Discovers MCP agent containers using Docker labels
- Monitors container lifecycle events
- Maintains real-time agent registry
- Handles Docker socket detection and fallback logic

**Rootless Docker Features**:
- Dynamic UID detection for user-specific socket paths
- Multiple socket path detection (`/run/user/{uid}/docker.sock`, `/tmp/docker-{uid}/docker.sock`)
- Enhanced retry logic optimized for rootless environments
- Security-focused: No root privileges or docker group membership required

#### 3. Router (`src/core/backend/router.js`)
**Purpose**: Intelligent tool call routing to appropriate agents
**Key Responsibilities**:
- Routes tool calls to the correct agent based on tool name
- Implements load balancing and failover logic
- Manages agent health and availability
- Provides circuit breaker functionality

#### 4. Validator (`src/core/backend/validator.js`)
**Purpose**: Input validation and schema enforcement
**Key Responsibilities**:
- Validates MCP JSON-RPC requests and responses
- Enforces tool input schemas
- Provides security validation for tool parameters
- Ensures protocol compliance

#### 5. Hardening (`src/core/backend/hardening.js`)
**Purpose**: Security and resilience features
**Key Responsibilities**:
- Implements security policies and access controls
- Provides rate limiting and request throttling
- Manages timeout and retry logic
- Implements circuit breaker patterns

#### 6. Registry (`src/core/backend/registry.js`)
**Purpose**: Runtime plugin and status management
**Key Responsibilities**:
- Maintains persistent registry of discovered agents
- Tracks agent status and health metrics
- Manages plugin metadata and capabilities
- Provides error logging and monitoring

## System Integration

### Docker Rootless Architecture

The core system is designed with Docker rootless as a first-class deployment target, providing enhanced security through user namespace isolation while maintaining full functionality.

#### Rootless Docker Benefits
- **Enhanced Security**: No root daemon process, reduced attack surface
- **User Isolation**: Containers run with user privileges only
- **No Privileged Access**: No need for sudo or root access
- **Namespace Isolation**: Enhanced container isolation through user namespaces

#### Core Rootless Features
1. **Socket Detection**: Automatically detects rootless Docker sockets
   - Primary: `/run/user/{uid}/docker.sock` (systemd user session)
   - Alternative: `/tmp/docker-{uid}/docker.sock` (manual installation)
   - Custom paths supported via `DOCKER_ROOTLESS_SOCKET_PATH`
   - No fallback to standard Docker sockets for security

2. **Permission Handling**: Adapts to rootless permission models
   - Dynamic UID detection and socket path resolution
   - Automatic user namespace mapping
   - Read-only socket access for security

3. **UID Management**: Dynamic UID detection and socket path resolution
   - Automatic current user ID detection
   - Container UID mapping for volume permissions
   - WSL2 compatibility with UID detection

4. **Fallback Logic**: Graceful degradation between rootless and standard modes
   - Automatic mode detection based on socket availability
   - Environment variable override support
   - Seamless switching without configuration changes

#### Rootless Deployment Prerequisites
- **Linux Kernel**: 4.18+ with user namespaces enabled
- **Packages**: `uidmap`, `dbus-user-session` (Ubuntu/Debian) or `shadow-utils`, `dbus-daemon` (CentOS/RHEL)
- **User Configuration**: Subordinate UID/GID ranges in `/etc/subuid` and `/etc/subgid`
- **Rootless Docker**: Installed via `curl -fsSL https://get.docker.com/rootless | sh`

#### Configuration Management
**Environment Variables**:
- `DOCKER_MODE=rootless` - Force rootless mode
- `DOCKER_USER_ID=$(id -u)` - Current user ID
- `DOCKER_ROOTLESS_SOCKET_PATH` - Custom socket path
- `MCP_TIMEOUT=45000` - Extended timeout for rootless mode
- `DISCOVERY_RETRY_ATTEMPTS=10` - Enhanced retry logic

**Compose Files**:
- `docker-compose.yml` - Unix/Linux rootless Docker configuration
- `docker-compose.windows.yml` - Windows Docker Desktop configuration
- Dynamic UID mounting: `/run/user/${DOCKER_USER_ID}:/run/user/${DOCKER_USER_ID}:ro` (Unix only)
- User namespace mapping with build args

### Deployment and Setup

#### Quick Rootless Setup
1. **Install Rootless Docker**:
   ```bash
   curl -fsSL https://get.docker.com/rootless | sh
   export PATH=/home/$USER/bin:$PATH
   export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
   systemctl --user enable docker
   systemctl --user start docker
   sudo loginctl enable-linger $USER
   ```

2. **Deploy MCP Orchestrator**:
   ```bash
   git clone https://github.com/neomint-research/mcp-orchestrator.git
   cd mcp-orchestrator
   ./scripts/deploy/start-rootless.sh -d
   ```

3. **Verify Deployment**:
   ```bash
   curl http://localhost:3000/health
   curl http://localhost:3000/agents
   ```

#### Configuration Management

Core system configuration is managed through:
- Environment variables (see `deploy/env/.env.core` and `deploy/env/.env.rootless`)
- Docker Compose configurations (`deploy/docker-compose.yml` for Unix/Linux and `deploy/docker-compose.windows.yml` for Windows)
- Runtime discovery and auto-configuration

**Rootless-Specific Configuration**:
```bash
# deploy/env/.env.rootless
DOCKER_MODE=rootless
DOCKER_ROOTLESS_SOCKET_PATH=/run/user/$(id -u)/docker.sock
MCP_TIMEOUT=45000
DISCOVERY_RETRY_ATTEMPTS=10
DISCOVERY_RETRY_DELAY=3000
ROOTLESS_MODE=true
```

### Error Handling and Resilience

The core system implements multiple layers of resilience:
- Circuit breaker patterns for agent communication
- Retry logic with exponential backoff
- Health monitoring and automatic recovery
- Graceful degradation when agents are unavailable

## Data Flow

1. **Initialization**: Orchestrator starts discovery process
2. **Agent Discovery**: Discovery component finds and registers agents
3. **Tool Aggregation**: Registry collects and validates tool definitions
4. **Request Processing**: Router directs tool calls to appropriate agents
5. **Response Handling**: Validator ensures response compliance
6. **Error Management**: Hardening component handles failures and retries

## Integration Points

### With Agent Modules
- Agents register through Docker labels
- Tools are discovered via MCP protocol
- Health checks maintain agent status

### With Docker Infrastructure
- Container discovery via Docker API
- Label-based agent identification
- Socket-based communication

### With Test Infrastructure
- Comprehensive test coverage for all components
- Integration tests for Docker configurations
- Rootless-specific test scenarios

## Performance Characteristics

- **Discovery Interval**: Configurable (default 30s)
- **Request Timeout**: 30s standard, 45s rootless
- **Circuit Breaker**: 5 failures trigger open state
- **Retry Logic**: 3-5 attempts with exponential backoff

## Troubleshooting

### Common Rootless Issues

#### Socket Permission Denied
**Symptoms**: `permission denied while trying to connect to the Docker daemon socket`

**Solutions**:
```bash
# Check socket permissions
ls -la /run/user/$(id -u)/docker.sock

# Restart rootless Docker
systemctl --user restart docker

# Set correct environment
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
```

#### Container Discovery Fails
**Symptoms**: No agents discovered, empty agent list

**Solutions**:
```bash
# Check Docker daemon status
systemctl --user status docker

# Verify socket path
echo $DOCKER_HOST

# Test Docker connectivity
docker version
```

#### UID Mismatch Issues
**Symptoms**: Permission errors, container startup failures

**Solutions**:
```bash
# Rebuild with correct UID
export DOCKER_USER_ID=$(id -u)
docker-compose build --build-arg USER_ID=$(id -u)
```

#### Slow Performance
**Solutions**:
```bash
# Increase timeouts in .env.core
MCP_TIMEOUT=60000
DISCOVERY_RETRY_ATTEMPTS=15
DISCOVERY_RETRY_DELAY=5000

# Optimize system settings
echo 'user.max_user_namespaces = 28633' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.ping_group_range = 0 2147483647' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Debug Mode
Enable debug logging for detailed troubleshooting:
```bash
export LOG_LEVEL=DEBUG
export DEBUG_MODE=true
export VERBOSE_LOGGING=true
./scripts/deploy/start-rootless.sh
```

## Security Considerations

- Read-only Docker socket access
- Input validation on all tool calls
- Rate limiting and request throttling
- Secure container communication
- Rootless privilege isolation
- User namespace isolation (rootless mode)
- No privileged container access
- Container-to-container network segmentation
