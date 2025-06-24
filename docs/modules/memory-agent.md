# Memory Agent Module

The Memory Agent provides persistent graph-based knowledge storage and retrieval capabilities, enabling MCP tools to maintain context and relationships across sessions.

## Overview

**Module Location**: `src/modules/memory-agent/`
**Container Port**: 3002
**Protocol**: HTTP/JSON-RPC
**Docker Labels**: `mcp.server=true`, `mcp.server.name=memory-agent`

## Capabilities

The Memory Agent implements four core knowledge management operations:

### 1. Store Knowledge (`store_knowledge`)
**Purpose**: Store knowledge items in the graph-based memory system
**Input Schema**:
```json
{
  "key": "string (required) - Unique identifier for the knowledge item",
  "content": "string (required) - The knowledge content to store",
  "metadata": {
    "type": "string (optional) - Knowledge type classification",
    "category": "string (optional) - Knowledge category",
    "tags": "array (optional) - Array of string tags",
    "source": "string (optional) - Source of the knowledge",
    "confidence": "number (optional) - Confidence score (0-1)"
  },
  "ttl": "number (optional) - Time to live in seconds"
}
```
**Returns**: Storage confirmation with knowledge ID and metadata

### 2. Query Knowledge (`query_knowledge`)
**Purpose**: Search and retrieve knowledge from the memory system
**Input Schema**:
```json
{
  "query": "string (required) - Search query or key to look for",
  "type": "string (optional) - Search type: exact, fuzzy, semantic, graph",
  "limit": "number (optional) - Maximum results (1-100, default: 10)",
  "includeMetadata": "boolean (optional) - Include metadata in results",
  "includeRelationships": "boolean (optional) - Include relationship information"
}
```
**Returns**: Array of matching knowledge items with scores and metadata

### 3. Create Relationship (`create_relationship`)
**Purpose**: Establish relationships between knowledge items
**Input Schema**:
```json
{
  "fromKey": "string (required) - Source knowledge item key",
  "toKey": "string (required) - Target knowledge item key",
  "relationshipType": "string (required) - Type of relationship",
  "strength": "number (optional) - Relationship strength (0-1)",
  "metadata": "object (optional) - Additional relationship metadata"
}
```
**Returns**: Relationship confirmation with relationship ID

### 4. Get Context (`get_context`)
**Purpose**: Retrieve contextual knowledge around a specific item
**Input Schema**:
```json
{
  "key": "string (required) - Central knowledge item key",
  "depth": "number (optional) - Relationship traversal depth (default: 2)",
  "relationshipTypes": "array (optional) - Filter by relationship types",
  "includeMetadata": "boolean (optional) - Include metadata in results"
}
```
**Returns**: Context graph with related knowledge items and relationships

## Knowledge Graph Architecture

### Storage Model
- **Nodes**: Individual knowledge items with unique keys
- **Edges**: Relationships between knowledge items with types and strengths
- **Metadata**: Rich metadata for both nodes and edges
- **TTL**: Automatic expiration for temporary knowledge

### Search Capabilities
- **Exact Match**: Direct key-based lookup
- **Fuzzy Search**: Approximate string matching
- **Semantic Search**: Content-based similarity (future enhancement)
- **Graph Traversal**: Relationship-based discovery

### Relationship Types
- **references**: One item references another
- **contains**: Hierarchical containment
- **relates_to**: General relationship
- **depends_on**: Dependency relationship
- **similar_to**: Similarity relationship
- **custom**: User-defined relationship types

## Persistence and Storage

### File-Based Storage
- Knowledge items stored as JSON files
- Relationships maintained in separate index files
- Atomic write operations for consistency
- Backup and recovery capabilities

### Data Organization
```
/app/memory/
├── knowledge/          # Individual knowledge items
│   ├── {key}.json     # Knowledge item files
│   └── index.json     # Knowledge index
├── relationships/      # Relationship data
│   ├── {id}.json      # Relationship files
│   └── index.json     # Relationship index
└── metadata/          # System metadata
    ├── stats.json     # Usage statistics
    └── config.json    # Configuration
```

## Configuration

### Environment Variables
- `MEMORY_AGENT_PORT`: Server port (default: 3002)
- `MEMORY_AGENT_HOST`: Server host (default: 0.0.0.0)
- `MEMORY_AGENT_STORAGE`: Storage directory (default: /app/memory)
- `LOG_LEVEL`: Logging level (default: INFO)

### Docker Configuration
**Dockerfile**: `environments/modules/memory-agent/Dockerfile`
**Base Image**: node:18-alpine
**User**: mcpuser (1001:1001)
**Volumes**: Persistent storage for memory data
**Health Check**: HTTP GET /health every 30s

## Integration

### With Core Orchestrator
- Discovered via Docker labels
- Tools registered through MCP protocol
- Health monitored via /health endpoint

### With Other Agents
- File Agent: Can store file-related knowledge
- Intent Agent: Can store intent patterns and responses
- Task Agent: Can store project and task relationships

### With Docker Rootless
- Compatible with rootless Docker environments
- Proper volume mounting for persistent storage
- Secure container isolation

## Usage Examples

### Storing Project Knowledge
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "store_knowledge",
    "arguments": {
      "key": "project-mcp-orchestrator",
      "content": "MCP Multi-Agent Orchestrator project with Docker rootless support",
      "metadata": {
        "type": "project",
        "category": "software",
        "tags": ["mcp", "docker", "orchestrator"],
        "confidence": 0.95
      }
    }
  }
}
```

### Creating Knowledge Relationships
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "create_relationship",
    "arguments": {
      "fromKey": "project-mcp-orchestrator",
      "toKey": "docker-rootless-config",
      "relationshipType": "depends_on",
      "strength": 0.8
    }
  }
}
```

## Performance Characteristics

- **Storage**: Efficient JSON-based file storage
- **Search**: Optimized indexing for fast retrieval
- **Memory Usage**: Lazy loading of knowledge items
- **Concurrency**: Thread-safe operations with file locking

## Placement Rationale

**NEOMINT-RESEARCH Decision Tree Analysis**:
- **System Necessity**: Optional (system can function without persistent memory)
- **Intention**: Provides knowledge persistence and relationship management
- **Substitutability**: Can be replaced with other memory/storage implementations
- **Placement**: `src/modules/` - Correctly placed as optional functional module
