#!/usr/bin/env node

/**
 * MCP File Agent - Backend Implementation
 * 
 * Provides file system operations through MCP protocol:
 * - read_file: Read file contents
 * - write_file: Write content to file
 * - list_directory: List directory contents
 * - create_directory: Create directories
 * - delete_file: Delete files and directories
 */

const http = require('http');
const fs = require('fs').promises;
const path = require('path');
const { FileTools } = require('./tools');

class FileAgentServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.FILE_AGENT_PORT || 3001,
            host: config.host || process.env.FILE_AGENT_HOST || '0.0.0.0',
            workingDirectory: config.workingDirectory || process.env.FILE_AGENT_WORKDIR || '/app/workspace',
            allowedPaths: config.allowedPaths || ['/app/workspace', '/tmp'],
            logLevel: config.logLevel || process.env.LOG_LEVEL || 'INFO',
            ...config
        };
        
        this.tools = new FileTools(this.config);
        this.server = null;
        this.initialized = false;
        
        this.log('INFO', 'File Agent Server initialized');
    }
    
    /**
     * Start the HTTP server
     */
    async start() {
        try {
            this.log('INFO', 'Starting File Agent Server...');
            
            // Ensure working directory exists
            await this.ensureWorkingDirectory();
            
            // Create HTTP server
            this.server = http.createServer((req, res) => {
                this.handleRequest(req, res);
            });
            
            // Start listening
            await new Promise((resolve, reject) => {
                this.server.listen(this.config.port, this.config.host, (error) => {
                    if (error) {
                        reject(error);
                    } else {
                        resolve();
                    }
                });
            });
            
            this.log('INFO', `File Agent Server started on ${this.config.host}:${this.config.port}`);
            this.log('INFO', `Working directory: ${this.config.workingDirectory}`);
            
        } catch (error) {
            this.log('ERROR', `Failed to start server: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Handle incoming HTTP requests
     */
    async handleRequest(req, res) {
        // Set CORS headers
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        
        // Handle preflight requests
        if (req.method === 'OPTIONS') {
            res.writeHead(200);
            res.end();
            return;
        }
        
        try {
            const url = new URL(req.url, `http://${req.headers.host}`);
            
            // Route requests
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
    
    /**
     * Handle MCP JSON-RPC requests
     */
    async handleMCPRequest(req, res) {
        if (req.method !== 'POST') {
            this.sendError(res, 405, 'Method Not Allowed', 'Only POST requests are allowed');
            return;
        }
        
        try {
            // Read request body
            const body = await this.readRequestBody(req);
            
            if (!body) {
                this.sendError(res, 400, 'Bad Request', 'Request body is required');
                return;
            }
            
            // Parse JSON
            let jsonRequest;
            try {
                jsonRequest = JSON.parse(body);
            } catch (error) {
                this.sendJSONRPCError(res, null, -32700, 'Parse error', 'Invalid JSON');
                return;
            }
            
            // Route to appropriate handler
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
            
            // Send success response
            this.sendJSONRPCSuccess(res, jsonRequest.id, result);
            
        } catch (error) {
            this.log('ERROR', `MCP request error: ${error.message}`);
            this.sendJSONRPCError(res, null, -32603, 'Internal error', error.message);
        }
    }
    
    /**
     * Handle initialize request
     */
    async handleInitialize(params) {
        this.initialized = true;
        this.log('INFO', 'File Agent initialized');
        
        return {
            protocolVersion: "2024-11-05",
            capabilities: {
                tools: {}
            },
            serverInfo: {
                name: "file-agent",
                version: "1.0.0"
            }
        };
    }
    
    /**
     * Handle tools/list request
     */
    async handleToolsList(params) {
        const tools = [
            {
                name: "read_file",
                description: "Read contents of a file",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string", description: "Path to the file to read" },
                        encoding: { type: "string", description: "File encoding", default: "utf8" }
                    },
                    required: ["path"]
                }
            },
            {
                name: "write_file",
                description: "Write content to a file",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string", description: "Path to the file to write" },
                        content: { type: "string", description: "Content to write" },
                        encoding: { type: "string", description: "File encoding", default: "utf8" },
                        createDirectories: { type: "boolean", description: "Create parent directories", default: false }
                    },
                    required: ["path", "content"]
                }
            },
            {
                name: "list_directory",
                description: "List contents of a directory",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string", description: "Path to the directory" },
                        recursive: { type: "boolean", description: "List recursively", default: false },
                        includeHidden: { type: "boolean", description: "Include hidden files", default: false }
                    },
                    required: ["path"]
                }
            },
            {
                name: "create_directory",
                description: "Create a directory",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string", description: "Path to create" },
                        recursive: { type: "boolean", description: "Create parent directories", default: false }
                    },
                    required: ["path"]
                }
            },
            {
                name: "delete_file",
                description: "Delete a file or directory",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string", description: "Path to delete" },
                        recursive: { type: "boolean", description: "Delete recursively", default: false },
                        force: { type: "boolean", description: "Force deletion", default: false }
                    },
                    required: ["path"]
                }
            }
        ];
        
        return { tools };
    }
    
    /**
     * Handle tools/call request
     */
    async handleToolCall(params) {
        if (!this.initialized) {
            throw new Error('Agent not initialized');
        }
        
        const { name: toolName, arguments: toolArgs } = params;
        
        this.log('INFO', `Executing tool: ${toolName}`);
        
        switch (toolName) {
            case 'read_file':
                return await this.tools.readFile(toolArgs);
            case 'write_file':
                return await this.tools.writeFile(toolArgs);
            case 'list_directory':
                return await this.tools.listDirectory(toolArgs);
            case 'create_directory':
                return await this.tools.createDirectory(toolArgs);
            case 'delete_file':
                return await this.tools.deleteFile(toolArgs);
            default:
                throw new Error(`Unknown tool: ${toolName}`);
        }
    }
    
    /**
     * Handle health check requests
     */
    async handleHealthCheck(req, res) {
        try {
            const health = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                workingDirectory: this.config.workingDirectory,
                initialized: this.initialized
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
    
    /**
     * Ensure working directory exists
     */
    async ensureWorkingDirectory() {
        try {
            await fs.access(this.config.workingDirectory);
        } catch (error) {
            this.log('INFO', `Creating working directory: ${this.config.workingDirectory}`);
            await fs.mkdir(this.config.workingDirectory, { recursive: true });
        }
    }
    
    /**
     * Read request body
     */
    readRequestBody(req) {
        return new Promise((resolve, reject) => {
            let body = '';
            
            req.on('data', (chunk) => {
                body += chunk.toString();
            });
            
            req.on('end', () => {
                resolve(body);
            });
            
            req.on('error', (error) => {
                reject(error);
            });
        });
    }
    
    /**
     * Send JSON-RPC success response
     */
    sendJSONRPCSuccess(res, id, result) {
        const response = {
            jsonrpc: '2.0',
            id: id,
            result: result
        };
        
        this.sendJSON(res, 200, response);
    }
    
    /**
     * Send JSON-RPC error response
     */
    sendJSONRPCError(res, id, code, message, data = null) {
        const response = {
            jsonrpc: '2.0',
            id: id,
            error: {
                code: code,
                message: message
            }
        };
        
        if (data !== null) {
            response.error.data = data;
        }
        
        this.sendJSON(res, 200, response);
    }
    
    /**
     * Send JSON response
     */
    sendJSON(res, statusCode, data) {
        res.writeHead(statusCode, {
            'Content-Type': 'application/json'
        });
        res.end(JSON.stringify(data, null, 2));
    }
    
    /**
     * Send error response
     */
    sendError(res, statusCode, title, message) {
        this.sendJSON(res, statusCode, {
            error: title,
            message: message,
            timestamp: new Date().toISOString()
        });
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [FileAgent] ${message}`);
    }
}

// Start server if this file is run directly
if (require.main === module) {
    const server = new FileAgentServer();
    
    server.start().catch((error) => {
        console.error('Failed to start File Agent server:', error);
        process.exit(1);
    });
}

module.exports = { FileAgentServer };
