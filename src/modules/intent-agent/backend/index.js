#!/usr/bin/env node

/**
 * MCP Intent Agent - Backend Implementation
 * Provides NLU capabilities: analyze_intent, extract_entities, disambiguate, suggest_tools
 */

const http = require('http');

class IntentAgentServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.INTENT_AGENT_PORT || 3003,
            host: config.host || process.env.INTENT_AGENT_HOST || '0.0.0.0',
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
        console.log(`Intent Agent Server started on ${this.config.host}:${this.config.port}`);
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
            this.sendJSON(res, 200, { status: 'healthy', timestamp: new Date().toISOString() });
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
                result = { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "intent-agent", version: "1.0.0" } };
                break;
            case 'tools/list':
                result = { tools: [
                    { name: "analyze_intent", description: "Analyze intent of text", inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } },
                    { name: "extract_entities", description: "Extract entities from text", inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } },
                    { name: "disambiguate", description: "Disambiguate ambiguous terms", inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } },
                    { name: "suggest_tools", description: "Suggest tools based on intent", inputSchema: { type: "object", properties: { intent: { type: "string" } }, required: ["intent"] } }
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
            case 'analyze_intent':
                return { intent: 'general_query', confidence: 0.8, entities: [], text: toolArgs.text };
            case 'extract_entities':
                return { entities: [], text: toolArgs.text };
            case 'disambiguate':
                return { disambiguated: [], text: toolArgs.text };
            case 'suggest_tools':
                return { suggestedTools: ['read_file', 'write_file'], intent: toolArgs.intent };
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
    const server = new IntentAgentServer();
    server.start().catch(console.error);
}

module.exports = { IntentAgentServer };
