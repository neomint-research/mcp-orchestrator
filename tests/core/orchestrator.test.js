/**
 * Core Orchestrator Unit Tests
 * 
 * Tests the MCP orchestrator core functionality including:
 * - Initialization
 * - Agent discovery
 * - Tool routing
 * - MCP protocol compliance
 */

const { MCPOrchestrator } = require('../../src/core/backend/orchestrator');

describe('MCP Orchestrator Core', () => {
    let orchestrator;
    
    beforeEach(() => {
        orchestrator = new MCPOrchestrator({
            port: 3000,
            logLevel: 'ERROR' // Reduce noise in tests
        });
    });
    
    afterEach(async () => {
        if (orchestrator && orchestrator.discovery) {
            orchestrator.discovery.stopDiscovery();
        }
    });
    
    describe('Initialization', () => {
        test('should initialize with default configuration', () => {
            expect(orchestrator).toBeDefined();
            expect(orchestrator.initialized).toBe(false);
            expect(orchestrator.agents.size).toBe(0);
            expect(orchestrator.toolRegistry.size).toBe(0);
        });
        
        test('should initialize with custom configuration', () => {
            const customOrchestrator = new MCPOrchestrator({
                port: 4000,
                discoveryInterval: 60000,
                timeout: 45000
            });
            
            expect(customOrchestrator.config.port).toBe(4000);
            expect(customOrchestrator.config.discoveryInterval).toBe(60000);
            expect(customOrchestrator.config.timeout).toBe(45000);
        });
        
        test('should validate initialization parameters', async () => {
            const result = await orchestrator.initialize({
                protocolVersion: "2024-11-05",
                capabilities: { tools: {} },
                clientInfo: { name: "test-client", version: "1.0.0" }
            });
            
            expect(result).toBeDefined();
            expect(result.protocolVersion).toBe("2024-11-05");
            expect(result.serverInfo.name).toBe("mcp-multi-agent-orchestrator");
            expect(orchestrator.initialized).toBe(true);
        });
        
        test('should reject invalid initialization parameters', async () => {
            await expect(orchestrator.initialize({
                protocolVersion: 123, // Invalid type
                capabilities: "invalid"
            })).rejects.toThrow();
        });
    });
    
    describe('Tool Management', () => {
        beforeEach(async () => {
            await orchestrator.initialize();
        });
        
        test('should list tools when no agents are available', async () => {
            const result = await orchestrator.listTools();
            
            expect(result).toBeDefined();
            expect(result.tools).toBeInstanceOf(Array);
            expect(result.tools.length).toBe(0);
        });
        
        test('should handle tool calls when no agents are available', async () => {
            await expect(orchestrator.callTool({
                name: "nonexistent_tool",
                arguments: {}
            })).rejects.toThrow('Unknown tool: nonexistent_tool');
        });
    });
    
    describe('Agent Management', () => {
        beforeEach(async () => {
            await orchestrator.initialize();
        });
        
        test('should handle agent loss gracefully', () => {
            const agentId = 'test-agent-123';
            
            // Simulate agent registration
            orchestrator.agents.set(agentId, {
                id: agentId,
                name: 'test-agent',
                status: 'active'
            });
            
            expect(orchestrator.agents.has(agentId)).toBe(true);
            
            // Simulate agent loss
            orchestrator.handleAgentLoss(agentId);
            
            const agent = orchestrator.agents.get(agentId);
            expect(agent.status).toBe('inactive');
        });
    });
    
    describe('Status and Health', () => {
        test('should provide status information', () => {
            const status = orchestrator.getStatus();
            
            expect(status).toBeDefined();
            expect(status.initialized).toBe(false);
            expect(status.agentCount).toBe(0);
            expect(status.toolCount).toBe(0);
            expect(status.activeAgents).toBe(0);
        });
        
        test('should update status after initialization', async () => {
            await orchestrator.initialize();
            
            const status = orchestrator.getStatus();
            expect(status.initialized).toBe(true);
        });
    });
    
    describe('Error Handling', () => {
        test('should handle initialization errors gracefully', async () => {
            // Mock a failing component
            orchestrator.registry.initialize = jest.fn().mockRejectedValue(new Error('Registry failed'));
            
            await expect(orchestrator.initialize()).rejects.toThrow('Registry failed');
        });
        
        test('should handle discovery errors gracefully', async () => {
            // Mock discovery failure
            orchestrator.discovery.discoverAgents = jest.fn().mockRejectedValue(new Error('Discovery failed'));
            
            await expect(orchestrator.initialize()).rejects.toThrow('Discovery failed');
        });
    });
    
    describe('MCP Protocol Compliance', () => {
        beforeEach(async () => {
            await orchestrator.initialize();
        });
        
        test('should return valid MCP initialize response', async () => {
            const result = await orchestrator.initialize();
            
            expect(result.protocolVersion).toBeDefined();
            expect(result.capabilities).toBeDefined();
            expect(result.serverInfo).toBeDefined();
            expect(result.serverInfo.name).toBe("mcp-multi-agent-orchestrator");
            expect(result.serverInfo.version).toBe("1.0.0");
        });
        
        test('should return valid MCP tools/list response', async () => {
            const result = await orchestrator.listTools();
            
            expect(result.tools).toBeInstanceOf(Array);
            // Each tool should have required MCP fields
            result.tools.forEach(tool => {
                expect(tool.name).toBeDefined();
                expect(tool.description).toBeDefined();
                expect(tool.inputSchema).toBeDefined();
                expect(tool.inputSchema.type).toBe('object');
            });
        });
        
        test('should validate tool call parameters', async () => {
            // Test missing name
            await expect(orchestrator.callTool({})).rejects.toThrow();
            
            // Test invalid name format
            await expect(orchestrator.callTool({
                name: "invalid tool name!",
                arguments: {}
            })).rejects.toThrow();
            
            // Test invalid arguments type
            await expect(orchestrator.callTool({
                name: "valid_tool",
                arguments: "invalid"
            })).rejects.toThrow();
        });
    });
});

// Mock implementations for testing
jest.mock('../../src/core/backend/discovery', () => ({
    Discovery: jest.fn().mockImplementation(() => ({
        discoverAgents: jest.fn().mockResolvedValue([]),
        startDiscovery: jest.fn(),
        stopDiscovery: jest.fn(),
        on: jest.fn(),
        getStatus: jest.fn().mockReturnValue({ isRunning: false })
    }))
}));

jest.mock('../../src/core/backend/router', () => ({
    Router: jest.fn().mockImplementation(() => ({
        on: jest.fn(),
        getStatus: jest.fn().mockReturnValue({ activeConnections: 0 })
    }))
}));

jest.mock('../../src/core/backend/validator', () => ({
    Validator: jest.fn().mockImplementation(() => ({
        validateInitialize: jest.fn().mockReturnValue({ valid: true }),
        validateToolCall: jest.fn().mockReturnValue({ valid: true }),
        getStatus: jest.fn().mockReturnValue({ strictMode: true })
    }))
}));

jest.mock('../../src/core/backend/hardening', () => ({
    Hardening: jest.fn().mockImplementation(() => ({
        safeToolCall: jest.fn().mockImplementation((fn) => fn()),
        getStatus: jest.fn().mockReturnValue({ circuitBreakers: {} })
    }))
}));

jest.mock('../../src/core/backend/registry', () => ({
    RegistryManager: jest.fn().mockImplementation(() => ({
        initialize: jest.fn().mockResolvedValue(),
        registerPlugin: jest.fn().mockResolvedValue(),
        logError: jest.fn().mockResolvedValue(),
        getStatus: jest.fn().mockReturnValue({ initialized: true })
    }))
}));
