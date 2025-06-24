# MCP Multi-Agent Orchestrator

A portable, memory-capable, docker-native orchestration layer for MCP tool agents with dynamic discovery, explicit intent routing, and test-driven development following NEOMINT-RESEARCH architecture patterns.

## Overview

The MCP Multi-Agent Orchestrator provides a unified endpoint for Model Context Protocol (MCP) tool calls, enabling seamless integration and orchestration of multiple specialized agent modules. Built with Docker-native architecture, it offers dynamic agent discovery, intelligent tool routing, and robust error handling.

## Key Features

- **Single Unified MCP Endpoint**: All tool calls go through one orchestrator
- **Dynamic Agent Discovery**: Automatically discovers MCP servers via Docker metadata
- **Rootless Docker Support**: Enhanced security with automatic rootless Docker detection
- **Explicit Intent Routing**: No implicit assumptions - all decisions require confirmation
- **Test-First Development**: Every component includes explicit success conditions
- **Self-Healing Architecture**: Automatic recovery and health monitoring
- **NEOMINT-RESEARCH Compliant**: Follows established architecture patterns

## Architecture

This project follows the NEOMINT-RESEARCH architecture with clear separation between:

- **Core System** (`src/core/`): Essential orchestration components
- **Agent Modules** (`src/modules/`): Optional MCP server implementations
- **Environments** (`environments/`): Docker containerization
- **Deployment** (`deploy/`): Compose configurations and environment setup
- **Registry** (`registry/`): Runtime plugin and status tracking
- **Tests** (`tests/`): Comprehensive test suites
- **Scripts** (`scripts/`): Automation and utility tools

## Quick Start

### Rootless Docker (Security-First Deployment)
The MCP Orchestrator is designed exclusively for rootless Docker deployment, providing enhanced security through user namespace isolation.

1. **Install Rootless Docker**:
   ```bash
   # Linux/WSL
   curl -fsSL https://get.docker.com/rootless | sh
   export PATH=/home/$USER/bin:$PATH
   export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
   systemctl --user enable docker
   systemctl --user start docker
   ```

2. **Setup and Deploy**:
   ```bash
   # One-click setup
   ./setup.ps1

   # Start services
   ./scripts/deploy/start-rootless.sh -d
   ```

3. **Verify Deployment**:
   ```bash
   curl http://localhost:3000/health
   ```

4. **Documentation**: See [Core System Guide](docs/core.md) and [System Overview](docs/system-overview.md)

## Agent Modules

The orchestrator includes four core agent modules:

- **File Agent**: File system operations (read, write, list, create, delete)
- **Memory Agent**: Knowledge storage and retrieval with graph relationships
- **Intent Agent**: Natural language understanding and intent analysis
- **Task Agent**: Project and task management with PiD-based orchestration

## Development

The system is designed for test-driven development with explicit success conditions for each component. All agents are containerized with proper MCP server labels for automatic discovery.

## NEOMINT-RESEARCH Architecture

This project strictly follows NEOMINT-RESEARCH patterns:
- Fixed directory structure with enforcement
- Core/Module separation
- Docker-native deployment
- Test-first development approach
- Explicit intent confirmation
- Self-maintaining systems