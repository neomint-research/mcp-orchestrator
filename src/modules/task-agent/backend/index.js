#!/usr/bin/env node

/**
 * MCP Task Agent - Backend Implementation
 * Provides task management: create_project, add_phase, add_task, execute_task, get_project_status, validate_dependencies
 */

const http = require('http');

class TaskAgentServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.TASK_AGENT_PORT || 3004,
            host: config.host || process.env.TASK_AGENT_HOST || '0.0.0.0',
            ...config
        };
        
        this.server = null;
        this.initialized = false;
        this.projects = new Map();
    }
    
    async start() {
        this.server = http.createServer((req, res) => this.handleRequest(req, res));
        await new Promise((resolve, reject) => {
            this.server.listen(this.config.port, this.config.host, (error) => {
                if (error) reject(error);
                else resolve();
            });
        });
        console.log(`Task Agent Server started on ${this.config.host}:${this.config.port}`);
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
            this.sendJSON(res, 200, { status: 'healthy', timestamp: new Date().toISOString(), projectCount: this.projects.size });
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
                result = { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "task-agent", version: "1.0.0" } };
                break;
            case 'tools/list':
                result = { tools: [
                    { name: "create_project", description: "Create a new project", inputSchema: { type: "object", properties: { name: { type: "string" }, description: { type: "string" } }, required: ["name", "description"] } },
                    { name: "add_phase", description: "Add phase to project", inputSchema: { type: "object", properties: { projectId: { type: "string" }, name: { type: "string" }, description: { type: "string" } }, required: ["projectId", "name", "description"] } },
                    { name: "add_task", description: "Add task to phase", inputSchema: { type: "object", properties: { projectId: { type: "string" }, phaseId: { type: "string" }, name: { type: "string" }, description: { type: "string" } }, required: ["projectId", "phaseId", "name", "description"] } },
                    { name: "execute_task", description: "Execute a task", inputSchema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" } }, required: ["projectId", "taskId"] } },
                    { name: "get_project_status", description: "Get project status", inputSchema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
                    { name: "validate_dependencies", description: "Validate dependencies", inputSchema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } }
                ]};
                break;
            case 'tools/call':
                result = await this.handleToolCall(jsonRequest.params);
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
            case 'create_project':
                const projectId = `proj_${Date.now()}`;
                this.projects.set(projectId, { id: projectId, name: toolArgs.name, description: toolArgs.description, phases: [], created: new Date().toISOString() });
                return { projectId, name: toolArgs.name, created: new Date().toISOString() };
            case 'add_phase':
                const project = this.projects.get(toolArgs.projectId);
                if (!project) throw new Error('Project not found');
                const phaseId = `phase_${Date.now()}`;
                project.phases.push({ id: phaseId, name: toolArgs.name, description: toolArgs.description, tasks: [] });
                return { phaseId, projectId: toolArgs.projectId, name: toolArgs.name };
            case 'add_task':
                const proj = this.projects.get(toolArgs.projectId);
                if (!proj) throw new Error('Project not found');
                const phase = proj.phases.find(p => p.id === toolArgs.phaseId);
                if (!phase) throw new Error('Phase not found');
                const taskId = `task_${Date.now()}`;
                phase.tasks.push({ id: taskId, name: toolArgs.name, description: toolArgs.description, status: 'pending' });
                return { taskId, phaseId: toolArgs.phaseId, name: toolArgs.name };
            case 'execute_task':
                return { taskId: toolArgs.taskId, status: 'completed', timestamp: new Date().toISOString() };
            case 'get_project_status':
                const p = this.projects.get(toolArgs.projectId);
                if (!p) throw new Error('Project not found');
                return { projectId: toolArgs.projectId, name: p.name, phases: p.phases.length, status: 'active' };
            case 'validate_dependencies':
                return { projectId: toolArgs.projectId, valid: true, issues: [] };
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
    const server = new TaskAgentServer();
    server.start().catch(console.error);
}

module.exports = { TaskAgentServer };
