# Task Agent Module

The Task Agent provides project and task management capabilities with PiD-based orchestration, enabling structured project planning, task tracking, and workflow coordination within the MCP ecosystem.

## Overview

**Module Location**: `src/modules/task-agent/`
**Container Port**: 3004
**Protocol**: HTTP/JSON-RPC
**Docker Labels**: `mcp.server=true`, `mcp.server.name=task-agent`

## Capabilities

The Task Agent implements six core project management operations:

### 1. Create Project (`create_project`)
**Purpose**: Initialize a new project with metadata and structure
**Input Schema**:
```json
{
  "name": "string (required) - Project name",
  "description": "string (optional) - Project description",
  "metadata": "object (optional) - Additional project metadata",
  "template": "string (optional) - Project template to use"
}
```
**Returns**: Project ID and creation confirmation with metadata

### 2. Add Phase (`add_phase`)
**Purpose**: Add a project phase with specific goals and timeline
**Input Schema**:
```json
{
  "projectId": "string (required) - Target project ID",
  "name": "string (required) - Phase name",
  "description": "string (optional) - Phase description",
  "dependencies": "array (optional) - Dependent phase IDs",
  "estimatedDuration": "number (optional) - Duration in days"
}
```
**Returns**: Phase ID and project structure update

### 3. Add Task (`add_task`)
**Purpose**: Create a task within a project phase
**Input Schema**:
```json
{
  "projectId": "string (required) - Target project ID",
  "phaseId": "string (required) - Target phase ID",
  "name": "string (required) - Task name",
  "description": "string (optional) - Task description",
  "priority": "string (optional) - Priority level (low, medium, high, critical)",
  "estimatedHours": "number (optional) - Estimated work hours",
  "dependencies": "array (optional) - Dependent task IDs"
}
```
**Returns**: Task ID and phase structure update

### 4. Execute Task (`execute_task`)
**Purpose**: Mark a task as executed and update its status
**Input Schema**:
```json
{
  "taskId": "string (required) - Task ID to execute",
  "status": "string (optional) - New status (pending, in_progress, completed, blocked)",
  "notes": "string (optional) - Execution notes",
  "actualHours": "number (optional) - Actual hours spent"
}
```
**Returns**: Task execution confirmation with updated status

### 5. Get Project Status (`get_project_status`)
**Purpose**: Retrieve comprehensive project status and progress
**Input Schema**:
```json
{
  "projectId": "string (required) - Project ID to query",
  "includeDetails": "boolean (optional) - Include detailed task information",
  "includeMetrics": "boolean (optional) - Include progress metrics"
}
```
**Returns**: Complete project status with phases, tasks, and progress metrics

### 6. Validate Dependencies (`validate_dependencies`)
**Purpose**: Check and validate project dependency chains
**Input Schema**:
```json
{
  "projectId": "string (required) - Project ID to validate",
  "checkCycles": "boolean (optional) - Check for circular dependencies",
  "suggestOptimizations": "boolean (optional) - Suggest workflow optimizations"
}
```
**Returns**: Dependency validation results with any issues and suggestions

## PiD-Based Orchestration

### Project-in-Development (PiD) Model
The Task Agent implements a PiD-based approach to project management:

#### Project Structure
```
Project
├── Phases (Sequential or Parallel)
│   ├── Tasks (Atomic work units)
│   ├── Dependencies (Inter-task relationships)
│   └── Deliverables (Phase outputs)
└── Metadata (Project-level information)
```

#### Orchestration Features
- **Dependency Management**: Automatic dependency resolution and validation
- **Progress Tracking**: Real-time progress calculation and reporting
- **Resource Allocation**: Task assignment and workload balancing
- **Timeline Management**: Schedule optimization and deadline tracking

### Task States and Transitions
- **pending**: Task created but not started
- **in_progress**: Task actively being worked on
- **completed**: Task finished successfully
- **blocked**: Task cannot proceed due to dependencies
- **cancelled**: Task cancelled or no longer needed

## Data Management

### Project Storage
Projects are stored as structured JSON documents with the following organization:

```json
{
  "id": "proj_timestamp",
  "name": "Project Name",
  "description": "Project Description",
  "created": "ISO timestamp",
  "status": "active|completed|cancelled",
  "phases": [
    {
      "id": "phase_timestamp",
      "name": "Phase Name",
      "description": "Phase Description",
      "status": "pending|in_progress|completed",
      "tasks": [
        {
          "id": "task_timestamp",
          "name": "Task Name",
          "description": "Task Description",
          "status": "pending|in_progress|completed|blocked",
          "priority": "low|medium|high|critical",
          "estimatedHours": 8,
          "actualHours": 6,
          "dependencies": ["task_id1", "task_id2"],
          "created": "ISO timestamp",
          "updated": "ISO timestamp"
        }
      ]
    }
  ],
  "metadata": {
    "template": "template_name",
    "tags": ["tag1", "tag2"],
    "owner": "user_id"
  }
}
```

### Persistence
- In-memory storage for current implementation
- Designed for future database integration
- Export/import capabilities for project data
- Backup and recovery support

## Configuration

### Environment Variables
- `TASK_AGENT_PORT`: Server port (default: 3004)
- `TASK_AGENT_HOST`: Server host (default: 0.0.0.0)
- `TASK_AGENT_STORAGE`: Storage directory for project data
- `LOG_LEVEL`: Logging level (default: INFO)

### Docker Configuration
**Dockerfile**: `environments/modules/task-agent/Dockerfile`
**Base Image**: node:18-alpine
**User**: mcpuser (1001:1001)
**Health Check**: HTTP GET /health every 30s

## Integration

### With Core Orchestrator
- Discovered via Docker labels
- Tools registered through MCP protocol
- Health monitored via /health endpoint

### With Other Agents
- **Memory Agent**: Store project knowledge and lessons learned
- **File Agent**: Manage project files and documentation
- **Intent Agent**: Interpret natural language project requests

### With Docker Rootless
- Compatible with rootless Docker environments
- Secure container isolation
- Efficient resource utilization

## Usage Examples

### Creating a New Project
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_project",
    "arguments": {
      "name": "MCP Orchestrator Enhancement",
      "description": "Enhance MCP orchestrator with new features",
      "metadata": {
        "template": "software_development",
        "priority": "high"
      }
    }
  }
}
```

### Adding Project Phases
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "add_phase",
    "arguments": {
      "projectId": "proj_1234567890",
      "name": "Requirements Analysis",
      "description": "Analyze and document requirements",
      "estimatedDuration": 5
    }
  }
}
```

### Checking Project Status
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "get_project_status",
    "arguments": {
      "projectId": "proj_1234567890",
      "includeDetails": true,
      "includeMetrics": true
    }
  }
}
```

## Performance Characteristics

- **Project Capacity**: Supports hundreds of projects with thousands of tasks
- **Response Time**: Sub-second response for typical operations
- **Memory Usage**: Efficient in-memory storage with lazy loading
- **Concurrency**: Thread-safe operations for multi-user environments

## Future Enhancements

- **Database Integration**: Persistent storage with SQL/NoSQL databases
- **Advanced Scheduling**: Critical path analysis and resource optimization
- **Collaboration Features**: Multi-user project management
- **Reporting**: Advanced analytics and progress reporting
- **Integration APIs**: External tool integration (Jira, GitHub, etc.)

## Placement Rationale

**NEOMINT-RESEARCH Decision Tree Analysis**:
- **System Necessity**: Optional (system can function without task management)
- **Intention**: Provides project and task orchestration capabilities
- **Substitutability**: Can be replaced with other project management implementations
- **Placement**: `src/modules/` - Correctly placed as optional functional module
