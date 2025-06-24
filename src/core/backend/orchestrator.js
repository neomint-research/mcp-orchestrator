/**
 * MCP Multi-Agent Orchestrator Core
 * 
 * Implements the main MCP server interface with endpoints:
 * - initialize: Initialize the orchestrator and discover agents
 * - tools/list: List all available tools from all agents
 * - tools/call: Route tool calls to appropriate agents
 */

const EventEmitter = require('events');
const { Discovery } = require('./discovery');
const { Router } = require('./router');
const { Validator } = require('./validator');
const { Hardening } = require('./hardening');
const { RegistryManager } = require('./registry');

class MCPOrchestrator extends EventEmitter {
    constructor(config = {}) {
        super();
        
        this.config = {
            port: config.port || process.env.ORCHESTRATOR_PORT || 3000,
            discoveryInterval: config.discoveryInterval || process.env.DISCOVERY_INTERVAL || 30000,
            timeout: config.timeout || process.env.MCP_TIMEOUT || 30000,
            logLevel: config.logLevel || process.env.LOG_LEVEL || 'INFO',
            ...config
        };
        
        this.initialized = false;
        this.agents = new Map();
        this.toolRegistry = new Map();
        
        // Initialize components
        this.discovery = new Discovery(this.config);
        this.router = new Router(this.config);
        this.validator = new Validator(this.config);
        this.hardening = new Hardening(this.config);
        this.registry = new RegistryManager(this.config);
        
        // Bind event handlers
        this.setupEventHandlers();
        
        this.log('INFO', 'MCP Orchestrator initialized');
    }
    
    /**
     * Initialize the orchestrator and discover agents
     */
    async initialize(params = {}) {
        try {
            this.log('INFO', 'Starting orchestrator initialization...');

            // Initialize registry
            await this.registry.initialize();

            // Validate initialization parameters
            const validationResult = this.validator.validateInitialize(params);
            if (!validationResult.valid) {
                throw new Error(`Invalid initialization parameters: ${validationResult.error}`);
            }

            // Detect Docker mode before discovery
            await this.discovery.detectDockerMode();

            // Discover available agents
            const discoveredAgents = await this.discovery.discoverAgents();
            this.log('INFO', `Discovered ${discoveredAgents.length} agents`);
            
            // Initialize each agent and collect their tools
            for (const agent of discoveredAgents) {
                try {
                    await this.initializeAgent(agent);
                } catch (error) {
                    this.log('WARN', `Failed to initialize agent ${agent.name}: ${error.message}`);
                    await this.registry.logError(agent.id, 'initialize', error);
                }
            }
            
            this.initialized = true;
            this.emit('initialized', { agentCount: this.agents.size, toolCount: this.toolRegistry.size });
            
            this.log('INFO', `Orchestrator initialized with ${this.agents.size} agents and ${this.toolRegistry.size} tools`);
            
            return {
                protocolVersion: "2024-11-05",
                capabilities: {
                    tools: {},
                    logging: {}
                },
                serverInfo: {
                    name: "mcp-multi-agent-orchestrator",
                    version: "1.0.0"
                }
            };
            
        } catch (error) {
            this.log('ERROR', `Initialization failed: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * List all available tools from all agents
     */
    async listTools(params = {}) {
        try {
            if (!this.initialized) {
                throw new Error('Orchestrator not initialized');
            }
            
            const tools = [];
            
            for (const [toolName, agentInfo] of this.toolRegistry) {
                const agent = this.agents.get(agentInfo.agentId);
                if (agent && agent.status === 'active') {
                    tools.push({
                        name: toolName,
                        description: agentInfo.description || `Tool provided by ${agentInfo.agentId}`,
                        inputSchema: agentInfo.inputSchema || {
                            type: "object",
                            properties: {},
                            required: []
                        }
                    });
                }
            }
            
            this.log('INFO', `Listed ${tools.length} available tools`);
            
            return { tools };
            
        } catch (error) {
            this.log('ERROR', `Failed to list tools: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Route tool calls to appropriate agents
     */
    async callTool(params) {
        try {
            if (!this.initialized) {
                throw new Error('Orchestrator not initialized');
            }
            
            // Validate tool call parameters
            const validationResult = this.validator.validateToolCall(params);
            if (!validationResult.valid) {
                throw new Error(`Invalid tool call: ${validationResult.error}`);
            }
            
            const { name: toolName, arguments: toolArgs } = params;
            
            // Find the agent responsible for this tool
            const agentInfo = this.toolRegistry.get(toolName);
            if (!agentInfo) {
                throw new Error(`Unknown tool: ${toolName}`);
            }
            
            const agent = this.agents.get(agentInfo.agentId);
            if (!agent) {
                throw new Error(`Agent not found for tool: ${toolName}`);
            }
            
            if (agent.status !== 'active') {
                throw new Error(`Agent ${agentInfo.agentId} is not active (status: ${agent.status})`);
            }
            
            // Route the tool call to the appropriate agent
            this.log('INFO', `Routing tool call ${toolName} to agent ${agentInfo.agentId}`);
            
            const result = await this.hardening.safeToolCall(
                () => this.router.routeToolCall(agent, toolName, toolArgs),
                this.config.timeout
            );
            
            this.emit('toolCallCompleted', { toolName, agentId: agentInfo.agentId, success: true });
            
            return result;
            
        } catch (error) {
            this.log('ERROR', `Tool call failed: ${error.message}`);
            this.emit('toolCallCompleted', { toolName: params?.name, success: false, error: error.message });
            throw error;
        }
    }
    
    /**
     * Initialize a single agent
     */
    async initializeAgent(agentConfig) {
        try {
            this.log('INFO', `Initializing agent: ${agentConfig.name}`);
            
            // Initialize the agent
            const initResult = await this.router.initializeAgent(agentConfig);
            
            // Get the agent's available tools
            const toolsResult = await this.router.getAgentTools(agentConfig);
            
            // Store agent information
            const agent = {
                id: agentConfig.id,
                name: agentConfig.name,
                config: agentConfig,
                status: 'active',
                tools: toolsResult.tools || [],
                lastHealthCheck: Date.now(),
                initResult
            };
            
            this.agents.set(agentConfig.id, agent);

            // Register tools in the tool registry
            for (const tool of agent.tools) {
                this.toolRegistry.set(tool.name, {
                    agentId: agentConfig.id,
                    description: tool.description,
                    inputSchema: tool.inputSchema
                });
            }

            // Register with registry manager
            await this.registry.registerPlugin(agentConfig, agent.tools);

            this.log('INFO', `Agent ${agentConfig.name} initialized with ${agent.tools.length} tools`);
            
        } catch (error) {
            this.log('ERROR', `Failed to initialize agent ${agentConfig.name}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Setup event handlers
     */
    setupEventHandlers() {
        this.discovery.on('agentDiscovered', (agent) => {
            this.log('INFO', `New agent discovered: ${agent.name}`);
        });
        
        this.discovery.on('agentLost', (agentId) => {
            this.log('WARN', `Agent lost: ${agentId}`);
            this.handleAgentLoss(agentId);
        });
        
        this.router.on('routingError', (error) => {
            this.log('ERROR', `Routing error: ${error.message}`);
        });
    }
    
    /**
     * Handle agent loss
     */
    handleAgentLoss(agentId) {
        const agent = this.agents.get(agentId);
        if (agent) {
            agent.status = 'inactive';
            this.log('WARN', `Marked agent ${agentId} as inactive`);
        }
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Orchestrator] ${message}`);
    }
    
    /**
     * Get orchestrator status
     */
    getStatus() {
        return {
            initialized: this.initialized,
            agentCount: this.agents.size,
            toolCount: this.toolRegistry.size,
            activeAgents: Array.from(this.agents.values()).filter(a => a.status === 'active').length,
            registry: this.registry ? this.registry.getStatus() : null
        };
    }
}

module.exports = { MCPOrchestrator };
