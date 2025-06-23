/**
 * Tool Routing Engine
 * 
 * Routes tool calls to the correct agent based on tool registry
 * Handles MCP protocol communication with agent containers
 */

const EventEmitter = require('events');
const http = require('http');
const https = require('https');

class Router extends EventEmitter {
    constructor(config = {}) {
        super();
        
        this.config = {
            timeout: config.timeout || 30000,
            retryAttempts: config.retryAttempts || 3,
            retryDelay: config.retryDelay || 1000,
            ...config
        };
        
        this.activeConnections = new Map();
        
        this.log('INFO', 'Tool Router initialized');
    }
    
    /**
     * Initialize an agent connection
     */
    async initializeAgent(agentConfig) {
        try {
            this.log('INFO', `Initializing agent connection: ${agentConfig.name}`);
            
            const initRequest = {
                jsonrpc: "2.0",
                id: this.generateRequestId(),
                method: "initialize",
                params: {
                    protocolVersion: "2024-11-05",
                    capabilities: {
                        tools: {}
                    },
                    clientInfo: {
                        name: "mcp-multi-agent-orchestrator",
                        version: "1.0.0"
                    }
                }
            };
            
            const response = await this.sendRequest(agentConfig, initRequest);
            
            if (response.error) {
                throw new Error(`Agent initialization failed: ${response.error.message}`);
            }
            
            this.log('INFO', `Agent ${agentConfig.name} initialized successfully`);
            return response.result;
            
        } catch (error) {
            this.log('ERROR', `Failed to initialize agent ${agentConfig.name}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Get available tools from an agent
     */
    async getAgentTools(agentConfig) {
        try {
            this.log('INFO', `Getting tools from agent: ${agentConfig.name}`);
            
            const toolsRequest = {
                jsonrpc: "2.0",
                id: this.generateRequestId(),
                method: "tools/list",
                params: {}
            };
            
            const response = await this.sendRequest(agentConfig, toolsRequest);
            
            if (response.error) {
                throw new Error(`Failed to get tools: ${response.error.message}`);
            }
            
            const tools = response.result?.tools || [];
            this.log('INFO', `Agent ${agentConfig.name} provides ${tools.length} tools`);
            
            return { tools };
            
        } catch (error) {
            this.log('ERROR', `Failed to get tools from agent ${agentConfig.name}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Route a tool call to the appropriate agent
     */
    async routeToolCall(agent, toolName, toolArgs) {
        try {
            this.log('INFO', `Routing tool call ${toolName} to agent ${agent.name}`);
            
            const toolCallRequest = {
                jsonrpc: "2.0",
                id: this.generateRequestId(),
                method: "tools/call",
                params: {
                    name: toolName,
                    arguments: toolArgs || {}
                }
            };
            
            const response = await this.sendRequest(agent.config, toolCallRequest);
            
            if (response.error) {
                this.emit('routingError', new Error(`Tool call failed: ${response.error.message}`));
                throw new Error(`Tool call failed: ${response.error.message}`);
            }
            
            this.log('INFO', `Tool call ${toolName} completed successfully`);
            return response.result;
            
        } catch (error) {
            this.log('ERROR', `Failed to route tool call ${toolName}: ${error.message}`);
            this.emit('routingError', error);
            throw error;
        }
    }
    
    /**
     * Send HTTP request to agent
     */
    async sendRequest(agentConfig, requestData) {
        const maxAttempts = this.config.retryAttempts;
        let lastError;
        
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                this.log('DEBUG', `Sending request to ${agentConfig.name} (attempt ${attempt}/${maxAttempts})`);
                
                const response = await this.makeHttpRequest(agentConfig, requestData);
                return response;
                
            } catch (error) {
                lastError = error;
                this.log('WARN', `Request attempt ${attempt} failed: ${error.message}`);
                
                if (attempt < maxAttempts) {
                    await this.delay(this.config.retryDelay * attempt);
                }
            }
        }
        
        throw lastError;
    }
    
    /**
     * Make HTTP request to agent
     */
    async makeHttpRequest(agentConfig, requestData) {
        return new Promise((resolve, reject) => {
            const connection = agentConfig.connection;
            const postData = JSON.stringify(requestData);
            
            const options = {
                hostname: connection.host,
                port: connection.port,
                path: '/mcp',
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(postData)
                },
                timeout: this.config.timeout
            };
            
            const httpModule = connection.protocol === 'https' ? https : http;
            
            const req = httpModule.request(options, (res) => {
                let data = '';
                
                res.on('data', (chunk) => {
                    data += chunk;
                });
                
                res.on('end', () => {
                    try {
                        if (res.statusCode !== 200) {
                            reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                            return;
                        }
                        
                        const response = JSON.parse(data);
                        resolve(response);
                        
                    } catch (error) {
                        reject(new Error(`Invalid JSON response: ${error.message}`));
                    }
                });
            });
            
            req.on('error', (error) => {
                reject(new Error(`Request failed: ${error.message}`));
            });
            
            req.on('timeout', () => {
                req.destroy();
                reject(new Error(`Request timeout after ${this.config.timeout}ms`));
            });
            
            req.write(postData);
            req.end();
        });
    }
    
    /**
     * Test agent connectivity
     */
    async testAgentConnection(agentConfig) {
        try {
            this.log('INFO', `Testing connection to agent: ${agentConfig.name}`);
            
            const pingRequest = {
                jsonrpc: "2.0",
                id: this.generateRequestId(),
                method: "ping",
                params: {}
            };
            
            const startTime = Date.now();
            await this.sendRequest(agentConfig, pingRequest);
            const responseTime = Date.now() - startTime;
            
            this.log('INFO', `Agent ${agentConfig.name} connection test successful (${responseTime}ms)`);
            return { success: true, responseTime };
            
        } catch (error) {
            this.log('ERROR', `Agent ${agentConfig.name} connection test failed: ${error.message}`);
            return { success: false, error: error.message };
        }
    }
    
    /**
     * Get connection status for an agent
     */
    getConnectionStatus(agentId) {
        return this.activeConnections.get(agentId) || { status: 'unknown' };
    }
    
    /**
     * Update connection status
     */
    updateConnectionStatus(agentId, status) {
        this.activeConnections.set(agentId, {
            status,
            lastUpdate: new Date().toISOString()
        });
    }
    
    /**
     * Generate unique request ID
     */
    generateRequestId() {
        return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }
    
    /**
     * Delay utility for retries
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Router] ${message}`);
    }
    
    /**
     * Get router status
     */
    getStatus() {
        return {
            activeConnections: this.activeConnections.size,
            config: {
                timeout: this.config.timeout,
                retryAttempts: this.config.retryAttempts,
                retryDelay: this.config.retryDelay
            }
        };
    }
    
    /**
     * Close all connections
     */
    close() {
        this.activeConnections.clear();
        this.log('INFO', 'Router closed, all connections cleared');
    }
}

module.exports = { Router };
