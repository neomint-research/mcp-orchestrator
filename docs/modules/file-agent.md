# File Agent Module

The File Agent provides secure file system operations through the MCP protocol, enabling controlled access to file and directory operations within containerized environments.

## Overview

**Module Location**: `src/modules/file-agent/`
**Container Port**: 3001
**Protocol**: HTTP/JSON-RPC
**Docker Labels**: `mcp.server=true`, `mcp.server.name=file-agent`

## Capabilities

The File Agent implements five core file operations:

### 1. Read File (`read_file`)
**Purpose**: Read contents of a file
**Input Schema**:
```json
{
  "path": "string (required) - File path to read",
  "encoding": "string (optional) - File encoding (default: utf8)",
  "maxSize": "number (optional) - Maximum file size in bytes"
}
```
**Returns**: File contents as string

### 2. Write File (`write_file`)
**Purpose**: Write content to a file
**Input Schema**:
```json
{
  "path": "string (required) - File path to write",
  "content": "string (required) - Content to write",
  "encoding": "string (optional) - File encoding (default: utf8)",
  "createDirectories": "boolean (optional) - Create parent directories"
}
```
**Returns**: Success confirmation with file metadata

### 3. List Directory (`list_directory`)
**Purpose**: List contents of a directory
**Input Schema**:
```json
{
  "path": "string (required) - Directory path to list",
  "recursive": "boolean (optional) - List recursively",
  "includeHidden": "boolean (optional) - Include hidden files",
  "pattern": "string (optional) - File pattern filter"
}
```
**Returns**: Array of file/directory entries with metadata

### 4. Create Directory (`create_directory`)
**Purpose**: Create a directory
**Input Schema**:
```json
{
  "path": "string (required) - Directory path to create",
  "recursive": "boolean (optional) - Create parent directories",
  "mode": "string (optional) - Directory permissions"
}
```
**Returns**: Success confirmation with directory metadata

### 5. Delete File (`delete_file`)
**Purpose**: Delete a file or directory
**Input Schema**:
```json
{
  "path": "string (required) - Path to delete",
  "recursive": "boolean (optional) - Delete recursively for directories",
  "force": "boolean (optional) - Force deletion without confirmation"
}
```
**Returns**: Success confirmation

## Security Model

### Path Restrictions
- Operations are restricted to allowed paths (default: `/app/workspace`, `/tmp`)
- Path traversal attacks are prevented through validation
- Symbolic links are handled securely

### File Size Limits
- Maximum file size: 10MB (configurable)
- Large file operations are rejected to prevent resource exhaustion

### Permission Model
- Runs as non-root user (mcpuser, UID 1001)
- Respects container filesystem permissions
- Compatible with Docker rootless security model

## Configuration

### Environment Variables
- `FILE_AGENT_PORT`: Server port (default: 3001)
- `FILE_AGENT_HOST`: Server host (default: 0.0.0.0)
- `FILE_AGENT_WORKDIR`: Working directory (default: /app/workspace)
- `LOG_LEVEL`: Logging level (default: INFO)

### Docker Configuration
**Dockerfile**: `environments/modules/file-agent/Dockerfile`
**Base Image**: node:18-alpine
**User**: mcpuser (1001:1001)
**Health Check**: HTTP GET /health every 30s

## Integration

### With Core Orchestrator
- Discovered via Docker labels
- Tools registered through MCP protocol
- Health monitored via /health endpoint

### With Docker Rootless
- Compatible with rootless Docker environments
- Proper UID/GID mapping for file permissions
- Secure container isolation

## Usage Examples

### Reading a Configuration File
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "read_file",
    "arguments": {
      "path": "/app/workspace/config.json",
      "encoding": "utf8"
    }
  }
}
```

### Creating a Project Structure
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "create_directory",
    "arguments": {
      "path": "/app/workspace/new-project",
      "recursive": true
    }
  }
}
```

## Error Handling

- **Path Not Found**: Returns 404-style error for missing files/directories
- **Permission Denied**: Returns 403-style error for access violations
- **File Too Large**: Returns 413-style error for oversized files
- **Invalid Path**: Returns 400-style error for malformed paths

## Performance Characteristics

- **Concurrent Operations**: Supports multiple simultaneous file operations
- **Memory Usage**: Streams large files to minimize memory footprint
- **Response Time**: Sub-second response for typical file operations
- **Throughput**: Optimized for container-to-container communication

## Placement Rationale

**NEOMINT-RESEARCH Decision Tree Analysis**:
- **System Necessity**: Optional (system can function without file operations)
- **Intention**: Provides file system abstraction for MCP tools
- **Substitutability**: Can be replaced with other file operation implementations
- **Placement**: `src/modules/` - Correctly placed as optional functional module
