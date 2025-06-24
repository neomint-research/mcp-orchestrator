# Intent Agent Module

The Intent Agent provides natural language understanding and intent analysis capabilities, enabling intelligent interpretation of user requests and tool suggestion within the MCP ecosystem.

## Overview

**Module Location**: `src/modules/intent-agent/`
**Container Port**: 3003
**Protocol**: HTTP/JSON-RPC
**Docker Labels**: `mcp.server=true`, `mcp.server.name=intent-agent`

## Capabilities

The Intent Agent implements four core natural language processing operations:

### 1. Analyze Intent (`analyze_intent`)
**Purpose**: Analyze natural language text to determine user intent
**Input Schema**:
```json
{
  "text": "string (required) - Natural language text to analyze",
  "context": "object (optional) - Additional context for analysis",
  "language": "string (optional) - Language code (default: en)",
  "includeEntities": "boolean (optional) - Include entity extraction"
}
```
**Returns**: Intent analysis with confidence scores and extracted entities

### 2. Extract Entities (`extract_entities`)
**Purpose**: Extract named entities and structured data from text
**Input Schema**:
```json
{
  "text": "string (required) - Text to extract entities from",
  "entityTypes": "array (optional) - Specific entity types to extract",
  "context": "object (optional) - Additional context for extraction"
}
```
**Returns**: Array of extracted entities with types, positions, and confidence scores

### 3. Disambiguate (`disambiguate`)
**Purpose**: Resolve ambiguous references and clarify intent
**Input Schema**:
```json
{
  "text": "string (required) - Ambiguous text to clarify",
  "candidates": "array (optional) - Possible interpretations",
  "context": "object (optional) - Context for disambiguation"
}
```
**Returns**: Ranked list of possible interpretations with confidence scores

### 4. Suggest Tools (`suggest_tools`)
**Purpose**: Recommend appropriate tools based on analyzed intent
**Input Schema**:
```json
{
  "intent": "string (required) - The analyzed intent",
  "availableTools": "array (optional) - List of available tools",
  "context": "object (optional) - Additional context for suggestions"
}
```
**Returns**: Ranked list of suggested tools with reasoning and confidence scores

## Intent Classification

### Supported Intent Categories

#### File Operations
- **read_intent**: User wants to read or view files
- **write_intent**: User wants to create or modify files
- **list_intent**: User wants to browse directories
- **delete_intent**: User wants to remove files/directories

#### Knowledge Management
- **store_intent**: User wants to save information
- **query_intent**: User wants to retrieve information
- **relate_intent**: User wants to create relationships
- **context_intent**: User wants contextual information

#### Task Management
- **create_project_intent**: User wants to start a new project
- **manage_task_intent**: User wants to handle tasks
- **status_intent**: User wants to check progress
- **plan_intent**: User wants to create plans

#### System Operations
- **health_intent**: User wants to check system status
- **config_intent**: User wants to modify configuration
- **help_intent**: User wants assistance or documentation

### Entity Types

#### File Entities
- **file_path**: File and directory paths
- **file_name**: File names and extensions
- **file_type**: File type classifications

#### Knowledge Entities
- **concept**: Abstract concepts and ideas
- **fact**: Factual information
- **relationship**: Relationship types and connections

#### Task Entities
- **project_name**: Project identifiers
- **task_name**: Task descriptions
- **deadline**: Time-based constraints
- **priority**: Priority levels

#### System Entities
- **agent_name**: MCP agent identifiers
- **tool_name**: Tool and function names
- **parameter**: Configuration parameters

## Natural Language Processing

### Text Analysis Pipeline
1. **Tokenization**: Break text into meaningful units
2. **Part-of-Speech Tagging**: Identify grammatical roles
3. **Named Entity Recognition**: Extract structured entities
4. **Intent Classification**: Determine user intent
5. **Confidence Scoring**: Assess analysis reliability

### Context Awareness
- **Conversation History**: Maintain context across interactions
- **Agent State**: Consider current system state
- **User Preferences**: Adapt to user patterns
- **Domain Knowledge**: Leverage MCP-specific understanding

## Configuration

### Environment Variables
- `INTENT_AGENT_PORT`: Server port (default: 3003)
- `INTENT_AGENT_HOST`: Server host (default: 0.0.0.0)
- `INTENT_AGENT_MODEL`: NLP model configuration
- `LOG_LEVEL`: Logging level (default: INFO)

### Docker Configuration
**Dockerfile**: `environments/modules/intent-agent/Dockerfile`
**Base Image**: node:18-alpine
**User**: mcpuser (1001:1001)
**Health Check**: HTTP GET /health every 30s

## Integration

### With Core Orchestrator
- Provides intelligent tool routing suggestions
- Enhances user experience with natural language interface
- Integrates with router for smart tool selection

### With Other Agents
- **File Agent**: Interprets file operation requests
- **Memory Agent**: Understands knowledge queries
- **Task Agent**: Processes project management requests

### With Docker Rootless
- Compatible with rootless Docker environments
- Secure container isolation
- Efficient resource utilization

## Usage Examples

### Analyzing User Intent
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "analyze_intent",
    "arguments": {
      "text": "I need to read the configuration file for the project",
      "includeEntities": true
    }
  }
}
```

### Getting Tool Suggestions
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "suggest_tools",
    "arguments": {
      "intent": "read_intent",
      "availableTools": ["read_file", "list_directory", "query_knowledge"],
      "context": {
        "entityTypes": ["file_path"],
        "entities": ["configuration file"]
      }
    }
  }
}
```

## Current Implementation Status

### Basic Implementation
The current implementation provides:
- Simple intent classification with predefined patterns
- Basic entity extraction for common types
- Tool suggestion based on intent mapping
- Placeholder responses for development and testing

### Future Enhancements
- Advanced NLP models for better accuracy
- Machine learning-based intent classification
- Context-aware conversation management
- Multi-language support
- Custom domain adaptation

## Performance Characteristics

- **Response Time**: Sub-second analysis for typical requests
- **Accuracy**: Pattern-based classification with room for ML enhancement
- **Memory Usage**: Lightweight implementation suitable for containers
- **Scalability**: Stateless design supports horizontal scaling

## Placement Rationale

**NEOMINT-RESEARCH Decision Tree Analysis**:
- **System Necessity**: Optional (system can function without NLU)
- **Intention**: Provides natural language understanding for enhanced UX
- **Substitutability**: Can be replaced with other NLP implementations
- **Placement**: `src/modules/` - Correctly placed as optional functional module
