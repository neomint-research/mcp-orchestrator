/**
 * Rootless Docker Integration Tests
 * 
 * Tests the complete rootless Docker integration including container discovery
 * and agent communication in rootless environments
 */

const { Discovery } = require('../../src/core/backend/discovery');
const { MCPOrchestrator } = require('../../src/core/backend/orchestrator');
const fs = require('fs');
const path = require('path');

describe('Rootless Docker Integration', () => {
    let discovery;
    let orchestrator;
    
    // Skip tests if not in a rootless Docker environment
    const isRootlessEnvironment = () => {
        const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '0');
        const rootlessSocket = `/run/user/${uid}/docker.sock`;
        return fs.existsSync(rootlessSocket);
    };

    beforeAll(() => {
        if (!isRootlessEnvironment()) {
            console.log('Skipping rootless Docker tests - not in rootless environment');
        }
    });

    beforeEach(() => {
        if (isRootlessEnvironment()) {
            discovery = new Discovery({
                logLevel: 'ERROR',
                dockerMode: 'auto'
            });
            orchestrator = new MCPOrchestrator({
                logLevel: 'ERROR'
            });
        }
    });

    afterEach(async () => {
        if (discovery) {
            discovery.stopDiscovery();
        }
        if (orchestrator) {
            await orchestrator.shutdown();
        }
    });

    describe('Rootless Docker Detection', () => {
        test('should detect rootless Docker mode automatically', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await discovery.detectDockerMode();
            
            expect(discovery.dockerMode).toBe('rootless');
            expect(discovery.dockerHost).toMatch(/^unix:\/\/\/run\/user\/\d+\/docker\.sock$/);
        }, 10000);

        test('should validate rootless socket accessibility', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '1001');
            const socketPath = `/run/user/${uid}/docker.sock`;
            
            const validation = await Discovery.validateDockerSocket(socketPath);
            
            expect(validation.valid).toBe(true);
            expect(validation.reason).toContain('accessible');
        }, 5000);

        test('should list Docker containers in rootless mode', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await discovery.detectDockerMode();
            const containers = await discovery.getDockerContainers();
            
            expect(Array.isArray(containers)).toBe(true);
            // Should not throw errors even if no containers are running
        }, 10000);
    });

    describe('Agent Discovery in Rootless Mode', () => {
        test('should discover MCP agents in rootless environment', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await discovery.detectDockerMode();
            const agents = await discovery.discoverAgents();
            
            expect(Array.isArray(agents)).toBe(true);
            
            // Validate agent structure if any are found
            agents.forEach(agent => {
                expect(agent).toHaveProperty('id');
                expect(agent).toHaveProperty('name');
                expect(agent).toHaveProperty('connection');
                expect(agent.connection).toHaveProperty('url');
                expect(agent).toHaveProperty('labels');
            });
        }, 15000);

        test('should handle container inspection in rootless mode', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await discovery.detectDockerMode();
            const containers = await discovery.getDockerContainers();
            
            // Test container inspection for each container
            for (const container of containers) {
                expect(container).toHaveProperty('id');
                expect(container).toHaveProperty('labels');
                expect(typeof container.labels).toBe('object');
            }
        }, 15000);
    });

    describe('Orchestrator Integration with Rootless Docker', () => {
        test('should initialize orchestrator with rootless Docker', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await orchestrator.initialize();
            
            expect(orchestrator.discovery.dockerMode).toBe('rootless');
            expect(orchestrator.initialized).toBe(true);
        }, 20000);

        test('should discover and register agents in rootless mode', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            await orchestrator.initialize();
            const agents = orchestrator.getAllAgents();
            
            expect(Array.isArray(agents)).toBe(true);
            
            // Validate registered agents
            agents.forEach(agent => {
                expect(agent).toHaveProperty('id');
                expect(agent).toHaveProperty('name');
                expect(agent).toHaveProperty('tools');
                expect(Array.isArray(agent.tools)).toBe(true);
            });
        }, 25000);
    });

    describe('Error Handling in Rootless Mode', () => {
        test('should handle missing rootless socket gracefully', async () => {
            const discovery = new Discovery({
                logLevel: 'ERROR',
                dockerMode: 'rootless',
                dockerRootlessSocket: '/nonexistent/socket'
            });

            await expect(discovery.detectDockerMode()).rejects.toThrow();
        });

        test('should not fallback to standard Docker - rootless only', async () => {
            const discovery = new Discovery({
                logLevel: 'ERROR',
                dockerRootlessSocket: '/nonexistent/socket'
            });

            // Should fail rather than fall back to standard Docker
            await expect(discovery.detectDockerMode()).rejects.toThrow('Rootless Docker is not available');
        });

        test('should retry Docker commands in rootless mode', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            const discovery = new Discovery({
                logLevel: 'ERROR',
                retryAttempts: 3,
                retryDelay: 100
            });

            await discovery.detectDockerMode();
            
            // This should succeed even with retries
            const containers = await discovery.getDockerContainers();
            expect(Array.isArray(containers)).toBe(true);
        }, 10000);
    });

    describe('Performance in Rootless Mode', () => {
        test('should detect Docker mode within reasonable time', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            const startTime = Date.now();
            await discovery.detectDockerMode();
            const endTime = Date.now();
            
            // Should complete within 5 seconds
            expect(endTime - startTime).toBeLessThan(5000);
        });

        test('should discover agents within reasonable time', async () => {
            if (!isRootlessEnvironment()) {
                return;
            }

            const startTime = Date.now();
            await discovery.detectDockerMode();
            await discovery.discoverAgents();
            const endTime = Date.now();
            
            // Should complete within 10 seconds
            expect(endTime - startTime).toBeLessThan(10000);
        });
    });
});
