#!/usr/bin/env node

/**
 * MCP Multi-Agent Orchestrator - Core Backend Entry Point
 * 
 * Starts the MCP server on configured port and handles incoming requests
 * Provides HTTP endpoint for MCP JSON-RPC communication
 */

const http = require('http');
const { MCPOrchestrator } = require('./orchestrator');

class MCPServer {
    constructor(config = {}) {
        this.config = {
            port: config.port || process.env.ORCHESTRATOR_PORT || 3000,
            host: config.host || process.env.ORCHESTRATOR_HOST || '0.0.0.0',
            logLevel: config.logLevel || process.env.LOG_LEVEL || 'INFO',
            ...config
        };
        
        this.orchestrator = new MCPOrchestrator(this.config);
        this.server = null;
        this.isShuttingDown = false;
        
        // Setup graceful shutdown
        this.setupGracefulShutdown();
        
        this.log('INFO', 'MCP Server initialized');
    }
    
    /**
     * Start the HTTP server
     */
    async start() {
        try {
            this.log('INFO', 'Starting MCP Server...');
            
            // Initialize the orchestrator
            await this.orchestrator.initialize();
            
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
            
            this.log('INFO', `MCP Server started on ${this.config.host}:${this.config.port}`);
            this.log('INFO', `Health check available at: http://${this.config.host}:${this.config.port}/health`);
            this.log('INFO', `MCP endpoint available at: http://${this.config.host}:${this.config.port}/mcp`);
            
            // Start agent discovery
            this.orchestrator.discovery.startDiscovery();
            
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
            } else if (url.pathname === '/status') {
                await this.handleStatusRequest(req, res);
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
            
            // Validate request
            const validation = this.orchestrator.validator.validateRequest(jsonRequest);
            if (!validation.valid) {
                this.sendJSONRPCError(res, jsonRequest.id, -32602, 'Invalid Request', validation.error);
                return;
            }
            
            // Route to appropriate handler
            let result;
            switch (jsonRequest.method) {
                case 'initialize':
                    result = await this.orchestrator.initialize(jsonRequest.params);
                    break;
                    
                case 'tools/list':
                    result = await this.orchestrator.listTools(jsonRequest.params);
                    break;
                    
                case 'tools/call':
                    result = await this.orchestrator.callTool(jsonRequest.params);
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
            
            // Determine error code
            let errorCode = -32603; // Internal error
            if (error.code && typeof error.code === 'number') {
                errorCode = error.code;
            }
            
            this.sendJSONRPCError(res, null, errorCode, 'Internal error', error.message);
        }
    }
    
    /**
     * Handle health check requests
     */
    async handleHealthCheck(req, res) {
        try {
            const status = this.orchestrator.getStatus();
            const health = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                orchestrator: status,
                discovery: this.orchestrator.discovery.getStatus(),
                router: this.orchestrator.router.getStatus(),
                hardening: this.orchestrator.hardening.getStatus()
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
     * Handle status requests
     */
    async handleStatusRequest(req, res) {
        try {
            const status = {
                server: {
                    port: this.config.port,
                    host: this.config.host,
                    uptime: process.uptime(),
                    memory: process.memoryUsage(),
                    version: process.version
                },
                orchestrator: this.orchestrator.getStatus(),
                agents: this.orchestrator.discovery.getAllAgents()
            };
            
            this.sendJSON(res, 200, status);
            
        } catch (error) {
            this.log('ERROR', `Status request error: ${error.message}`);
            this.sendError(res, 500, 'Internal Server Error', error.message);
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
     * Setup graceful shutdown
     */
    setupGracefulShutdown() {
        const shutdown = async (signal) => {
            if (this.isShuttingDown) {
                return;
            }
            
            this.isShuttingDown = true;
            this.log('INFO', `Received ${signal}, shutting down gracefully...`);
            
            try {
                // Stop discovery
                if (this.orchestrator.discovery) {
                    this.orchestrator.discovery.stopDiscovery();
                }
                
                // Close server
                if (this.server) {
                    await new Promise((resolve) => {
                        this.server.close(resolve);
                    });
                }
                
                this.log('INFO', 'Server shutdown complete');
                process.exit(0);
                
            } catch (error) {
                this.log('ERROR', `Shutdown error: ${error.message}`);
                process.exit(1);
            }
        };
        
        process.on('SIGTERM', () => shutdown('SIGTERM'));
        process.on('SIGINT', () => shutdown('SIGINT'));
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Server] ${message}`);
    }
}

// Start server if this file is run directly
if (require.main === module) {
    const server = new MCPServer();
    
    server.start().catch((error) => {
        console.error('Failed to start server:', error);
        process.exit(1);
    });
}

module.exports = { MCPServer };
