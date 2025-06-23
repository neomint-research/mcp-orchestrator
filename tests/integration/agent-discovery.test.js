/**
 * Agent Discovery Integration Tests
 * 
 * Tests the complete discover-register-route-execute cycle for all agents
 */

const { MCPOrchestrator } = require('../../src/core/backend/orchestrator');
const { Discovery } = require('../../src/core/backend/discovery');

describe('Agent Discovery Integration', () => {
    let orchestrator;
    let discovery;
    
    beforeEach(() => {
        orchestrator = new MCPOrchestrator({
            logLevel: 'ERROR'
        });
        discovery = new Discovery({
            logLevel: 'ERROR'
        });
    });
    
    afterEach(async () => {
        if (discovery) {
            discovery.stopDiscovery();
        }
    });
    
    describe('Docker Container Discovery', () => {
        test('should discover MCP server containers', async () => {
            // This test requires Docker to be running with MCP containers
            const agents = await discovery.discoverAgents();
            
            expect(agents).toBeInstanceOf(Array);
            
            // If containers are running, validate their structure
            agents.forEach(agent => {
                expect(agent.id).toBeDefined();
                expect(agent.name).toBeDefined();
                expect(agent.connection).toBeDefined();
                expect(agent.connection.url).toBeDefined();
                expect(agent.labels).toBeDefined();
                expect(agent.labels['mcp.server']).toBe('true');
            });
        });
        
        test('should handle Docker unavailability gracefully', async () => {
            // Mock Docker unavailability
            const originalGetDockerContainers = discovery.getDockerContainers;
            discovery.getDockerContainers = jest.fn().mockRejectedValue(new Error('Docker not available'));
            
            await expect(discovery.discoverAgents()).rejects.toThrow();
            
            // Restore original method
            discovery.getDockerContainers = originalGetDockerContainers;
        });
    });
    
    describe('Agent Registration', () => {
        test('should register discovered agents with orchestrator', async () => {
            await orchestrator.initialize();
            
            // Mock discovered agents
            const mockAgents = [
                {
                    id: 'test-file-agent',
                    name: 'file-agent',
                    connection: { url: 'http://localhost:3001' },
                    labels: { 'mcp.server': 'true', 'mcp.server.name': 'file-agent' }
                }
            ];
            
            orchestrator.discovery.discoverAgents = jest.fn().mockResolvedValue(mockAgents);
            orchestrator.router.initializeAgent = jest.fn().mockResolvedValue({});
            orchestrator.router.getAgentTools = jest.fn().mockResolvedValue({
                tools: [
                    { name: 'read_file', description: 'Read file contents' },
                    { name: 'write_file', description: 'Write file contents' }
                ]
            });
            
            await orchestrator.initialize();
            
            expect(orchestrator.agents.size).toBe(1);
            expect(orchestrator.toolRegistry.size).toBe(2);
            expect(orchestrator.toolRegistry.has('read_file')).toBe(true);
            expect(orchestrator.toolRegistry.has('write_file')).toBe(true);
        });
    });
    
    describe('Tool Registry Management', () => {
        test('should maintain tool-to-agent mapping', async () => {
            await orchestrator.initialize();
            
            // Mock multiple agents with different tools
            const mockAgents = [
                {
                    id: 'file-agent',
                    name: 'file-agent',
                    connection: { url: 'http://localhost:3001' },
                    labels: { 'mcp.server': 'true' }
                },
                {
                    id: 'memory-agent',
                    name: 'memory-agent',
                    connection: { url: 'http://localhost:3002' },
                    labels: { 'mcp.server': 'true' }
                }
            ];
            
            orchestrator.discovery.discoverAgents = jest.fn().mockResolvedValue(mockAgents);
            
            // Mock different tools for each agent
            orchestrator.router.initializeAgent = jest.fn().mockResolvedValue({});
            orchestrator.router.getAgentTools = jest.fn()
                .mockResolvedValueOnce({
                    tools: [{ name: 'read_file', description: 'Read file' }]
                })
                .mockResolvedValueOnce({
                    tools: [{ name: 'store_knowledge', description: 'Store knowledge' }]
                });
            
            await orchestrator.initialize();
            
            expect(orchestrator.toolRegistry.get('read_file').agentId).toBe('file-agent');
            expect(orchestrator.toolRegistry.get('store_knowledge').agentId).toBe('memory-agent');
        });
    });
    
    describe('Agent Health Monitoring', () => {
        test('should track agent status', async () => {
            await orchestrator.initialize();
            
            const agentId = 'test-agent';
            const mockAgent = {
                id: agentId,
                name: 'test-agent',
                status: 'active'
            };
            
            orchestrator.agents.set(agentId, mockAgent);
            
            // Simulate agent becoming inactive
            orchestrator.handleAgentLoss(agentId);
            
            const agent = orchestrator.agents.get(agentId);
            expect(agent.status).toBe('inactive');
        });
    });
    
    describe('Error Recovery', () => {
        test('should continue operation when some agents fail to initialize', async () => {
            await orchestrator.initialize();
            
            const mockAgents = [
                {
                    id: 'working-agent',
                    name: 'working-agent',
                    connection: { url: 'http://localhost:3001' },
                    labels: { 'mcp.server': 'true' }
                },
                {
                    id: 'failing-agent',
                    name: 'failing-agent',
                    connection: { url: 'http://localhost:3002' },
                    labels: { 'mcp.server': 'true' }
                }
            ];
            
            orchestrator.discovery.discoverAgents = jest.fn().mockResolvedValue(mockAgents);
            
            // Mock one agent succeeding and one failing
            orchestrator.router.initializeAgent = jest.fn()
                .mockResolvedValueOnce({})
                .mockRejectedValueOnce(new Error('Agent failed to initialize'));
            
            orchestrator.router.getAgentTools = jest.fn()
                .mockResolvedValueOnce({
                    tools: [{ name: 'working_tool', description: 'Working tool' }]
                });
            
            await orchestrator.initialize();
            
            // Should have registered the working agent
            expect(orchestrator.agents.size).toBe(1);
            expect(orchestrator.agents.has('working-agent')).toBe(true);
            expect(orchestrator.toolRegistry.has('working_tool')).toBe(true);
        });
    });
});

// Integration test helpers
const testHelpers = {
    /**
     * Wait for condition to be true
     */
    async waitFor(condition, timeout = 5000) {
        const start = Date.now();
        while (Date.now() - start < timeout) {
            if (await condition()) {
                return true;
            }
            await new Promise(resolve => setTimeout(resolve, 100));
        }
        throw new Error('Timeout waiting for condition');
    },
    
    /**
     * Create mock agent configuration
     */
    createMockAgent(name, port, tools = []) {
        return {
            id: `mock-${name}`,
            name: name,
            connection: { url: `http://localhost:${port}` },
            labels: {
                'mcp.server': 'true',
                'mcp.server.name': name,
                'mcp.server.port': port.toString()
            },
            tools: tools
        };
    }
};

module.exports = { testHelpers };
