#!/usr/bin/env node

/**
 * MCP Memory Agent - Backend Implementation
 * 
 * Provides graph-based knowledge storage through MCP protocol:
 * - store_knowledge: Store knowledge items
 * - query_knowledge: Search and retrieve knowledge
 * - create_relationship: Create relationships between items
 * - get_context: Get contextual information
 */

const http = require('http');
const { MemoryTools } = require('./tools');

class MemoryAgentServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.MEMORY_AGENT_PORT || 3002,
            host: config.host || process.env.MEMORY_AGENT_HOST || '0.0.0.0',
            dataDirectory: config.dataDirectory || process.env.MEMORY_AGENT_DATA || '/app/data',
            logLevel: config.logLevel || process.env.LOG_LEVEL || 'INFO',
            ...config
        };
        
        this.tools = new MemoryTools(this.config);
        this.server = null;
        this.initialized = false;
        
        this.log('INFO', 'Memory Agent Server initialized');
    }
    
    async start() {
        try {
            this.log('INFO', 'Starting Memory Agent Server...');
            
            await this.tools.initialize();
            
            this.server = http.createServer((req, res) => {
                this.handleRequest(req, res);
            });
            
            await new Promise((resolve, reject) => {
                this.server.listen(this.config.port, this.config.host, (error) => {
                    if (error) reject(error);
                    else resolve();
                });
            });
            
            this.log('INFO', `Memory Agent Server started on ${this.config.host}:${this.config.port}`);
            
        } catch (error) {
            this.log('ERROR', `Failed to start server: ${error.message}`);
            throw error;
        }
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
        
        try {
            const url = new URL(req.url, `http://${req.headers.host}`);
            
            if (url.pathname === '/health') {
                await this.handleHealthCheck(req, res);
            } else if (url.pathname === '/mcp') {
                await this.handleMCPRequest(req, res);
            } else {
                this.sendError(res, 404, 'Not Found', 'Endpoint not found');
            }
            
        } catch (error) {
            this.log('ERROR', `Request handling error: ${error.message}`);
            this.sendError(res, 500, 'Internal Server Error', error.message);
        }
    }
    
    async handleMCPRequest(req, res) {
        if (req.method !== 'POST') {
            this.sendError(res, 405, 'Method Not Allowed', 'Only POST requests are allowed');
            return;
        }
        
        try {
            const body = await this.readRequestBody(req);
            if (!body) {
                this.sendError(res, 400, 'Bad Request', 'Request body is required');
                return;
            }
            
            let jsonRequest;
            try {
                jsonRequest = JSON.parse(body);
            } catch (error) {
                this.sendJSONRPCError(res, null, -32700, 'Parse error', 'Invalid JSON');
                return;
            }
            
            let result;
            switch (jsonRequest.method) {
                case 'initialize':
                    result = await this.handleInitialize(jsonRequest.params);
                    break;
                case 'tools/list':
                    result = await this.handleToolsList(jsonRequest.params);
                    break;
                case 'tools/call':
                    result = await this.handleToolCall(jsonRequest.params);
                    break;
                case 'ping':
                    result = { pong: true, timestamp: new Date().toISOString() };
                    break;
                default:
                    this.sendJSONRPCError(res, jsonRequest.id, -32601, 'Method not found', `Unknown method: ${jsonRequest.method}`);
                    return;
            }
            
            this.sendJSONRPCSuccess(res, jsonRequest.id, result);
            
        } catch (error) {
            this.log('ERROR', `MCP request error: ${error.message}`);
            this.sendJSONRPCError(res, null, -32603, 'Internal error', error.message);
        }
    }
    
    async handleInitialize(params) {
        this.initialized = true;
        this.log('INFO', 'Memory Agent initialized');
        
        return {
            protocolVersion: "2024-11-05",
            capabilities: { tools: {} },
            serverInfo: { name: "memory-agent", version: "1.0.0" }
        };
    }
    
    async handleToolsList(params) {
        const tools = [
            {
                name: "store_knowledge",
                description: "Store knowledge in the graph-based memory system",
                inputSchema: {
                    type: "object",
                    properties: {
                        key: { type: "string", description: "Unique identifier" },
                        content: { type: "string", description: "Knowledge content" },
                        metadata: { type: "object", description: "Additional metadata" }
                    },
                    required: ["key", "content"]
                }
            },
            {
                name: "query_knowledge",
                description: "Query knowledge from the memory system",
                inputSchema: {
                    type: "object",
                    properties: {
                        query: { type: "string", description: "Search query" },
                        type: { type: "string", description: "Search type", default: "fuzzy" },
                        limit: { type: "number", description: "Max results", default: 10 }
                    },
                    required: ["query"]
                }
            },
            {
                name: "create_relationship",
                description: "Create a relationship between knowledge items",
                inputSchema: {
                    type: "object",
                    properties: {
                        fromKey: { type: "string", description: "Source key" },
                        toKey: { type: "string", description: "Target key" },
                        relationshipType: { type: "string", description: "Relationship type" }
                    },
                    required: ["fromKey", "toKey", "relationshipType"]
                }
            },
            {
                name: "get_context",
                description: "Get contextual information around a knowledge item",
                inputSchema: {
                    type: "object",
                    properties: {
                        key: { type: "string", description: "Knowledge item key" },
                        depth: { type: "number", description: "Relationship depth", default: 2 }
                    },
                    required: ["key"]
                }
            }
        ];
        
        return { tools };
    }
    
    async handleToolCall(params) {
        if (!this.initialized) {
            throw new Error('Agent not initialized');
        }
        
        const { name: toolName, arguments: toolArgs } = params;
        this.log('INFO', `Executing tool: ${toolName}`);
        
        switch (toolName) {
            case 'store_knowledge':
                return await this.tools.storeKnowledge(toolArgs);
            case 'query_knowledge':
                return await this.tools.queryKnowledge(toolArgs);
            case 'create_relationship':
                return await this.tools.createRelationship(toolArgs);
            case 'get_context':
                return await this.tools.getContext(toolArgs);
            default:
                throw new Error(`Unknown tool: ${toolName}`);
        }
    }
    
    async handleHealthCheck(req, res) {
        try {
            const health = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                initialized: this.initialized,
                knowledgeCount: await this.tools.getKnowledgeCount()
            };
            
            this.sendJSON(res, 200, health);
            
        } catch (error) {
            this.log('ERROR', `Health check error: ${error.message}`);
            this.sendJSON(res, 503, {
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            });
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
    
    sendJSONRPCError(res, id, code, message, data = null) {
        const response = { jsonrpc: '2.0', id: id, error: { code: code, message: message } };
        if (data !== null) response.error.data = data;
        this.sendJSON(res, 200, response);
    }
    
    sendJSON(res, statusCode, data) {
        res.writeHead(statusCode, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data, null, 2));
    }
    
    sendError(res, statusCode, title, message) {
        this.sendJSON(res, statusCode, {
            error: title,
            message: message,
            timestamp: new Date().toISOString()
        });
    }
    
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [MemoryAgent] ${message}`);
    }
}

if (require.main === module) {
    const server = new MemoryAgentServer();
    server.start().catch((error) => {
        console.error('Failed to start Memory Agent server:', error);
        process.exit(1);
    });
}

module.exports = { MemoryAgentServer };
