/**
 * Docker-based Agent Discovery
 * 
 * Discovers MCP agent containers using Docker labels and extracts connection data
 * Monitors for container lifecycle events and maintains agent registry
 */

const EventEmitter = require('events');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class Discovery extends EventEmitter {
    constructor(config = {}) {
        super();
        
        this.config = {
            discoveryInterval: config.discoveryInterval || 30000,
            dockerSocket: config.dockerSocket || '/var/run/docker.sock',
            labelFilter: config.labelFilter || 'mcp.server=true',
            ...config
        };
        
        this.knownAgents = new Map();
        this.discoveryTimer = null;
        this.isDiscovering = false;
        
        this.log('INFO', 'Docker Discovery initialized');
    }
    
    /**
     * Start continuous agent discovery
     */
    startDiscovery() {
        if (this.discoveryTimer) {
            this.log('WARN', 'Discovery already running');
            return;
        }
        
        this.log('INFO', 'Starting continuous agent discovery');
        
        // Initial discovery
        this.discoverAgents().catch(error => {
            this.log('ERROR', `Initial discovery failed: ${error.message}`);
        });
        
        // Set up periodic discovery
        this.discoveryTimer = setInterval(() => {
            if (!this.isDiscovering) {
                this.discoverAgents().catch(error => {
                    this.log('ERROR', `Periodic discovery failed: ${error.message}`);
                });
            }
        }, this.config.discoveryInterval);
    }
    
    /**
     * Stop continuous agent discovery
     */
    stopDiscovery() {
        if (this.discoveryTimer) {
            clearInterval(this.discoveryTimer);
            this.discoveryTimer = null;
            this.log('INFO', 'Stopped continuous agent discovery');
        }
    }
    
    /**
     * Discover all MCP agent containers
     */
    async discoverAgents() {
        if (this.isDiscovering) {
            this.log('DEBUG', 'Discovery already in progress, skipping');
            return Array.from(this.knownAgents.values());
        }
        
        this.isDiscovering = true;
        
        try {
            this.log('INFO', 'Starting agent discovery...');
            
            // Get all containers with MCP server label
            const containers = await this.getDockerContainers();
            const mcpContainers = containers.filter(container => 
                this.isMCPServer(container)
            );
            
            this.log('INFO', `Found ${mcpContainers.length} MCP server containers`);
            
            const discoveredAgents = [];
            const currentAgentIds = new Set();
            
            for (const container of mcpContainers) {
                try {
                    const agent = await this.extractAgentInfo(container);
                    if (agent) {
                        discoveredAgents.push(agent);
                        currentAgentIds.add(agent.id);
                        
                        // Check if this is a new agent
                        if (!this.knownAgents.has(agent.id)) {
                            this.knownAgents.set(agent.id, agent);
                            this.emit('agentDiscovered', agent);
                            this.log('INFO', `New agent discovered: ${agent.name} (${agent.id})`);
                        } else {
                            // Update existing agent info
                            this.knownAgents.set(agent.id, agent);
                        }
                    }
                } catch (error) {
                    this.log('ERROR', `Failed to extract agent info from container ${container.id}: ${error.message}`);
                }
            }
            
            // Check for agents that are no longer available
            for (const [agentId, agent] of this.knownAgents) {
                if (!currentAgentIds.has(agentId)) {
                    this.knownAgents.delete(agentId);
                    this.emit('agentLost', agentId);
                    this.log('WARN', `Agent lost: ${agent.name} (${agentId})`);
                }
            }
            
            this.log('INFO', `Discovery complete. Active agents: ${discoveredAgents.length}`);
            return discoveredAgents;
            
        } catch (error) {
            this.log('ERROR', `Agent discovery failed: ${error.message}`);
            throw error;
        } finally {
            this.isDiscovering = false;
        }
    }
    
    /**
     * Get all Docker containers
     */
    async getDockerContainers() {
        try {
            const command = 'docker ps --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}" --filter "status=running"';
            const { stdout } = await execAsync(command);
            
            if (!stdout.trim()) {
                return [];
            }
            
            const containers = stdout.trim().split('\n').map(line => {
                const [id, names, image, status, ports] = line.split('|');
                return {
                    id: id.trim(),
                    names: names.trim(),
                    image: image.trim(),
                    status: status.trim(),
                    ports: ports.trim()
                };
            });
            
            // Get detailed info including labels for each container
            const detailedContainers = await Promise.all(
                containers.map(async (container) => {
                    try {
                        const inspectCommand = `docker inspect ${container.id}`;
                        const { stdout: inspectOutput } = await execAsync(inspectCommand);
                        const inspectData = JSON.parse(inspectOutput)[0];
                        
                        return {
                            ...container,
                            labels: inspectData.Config.Labels || {},
                            networkSettings: inspectData.NetworkSettings,
                            config: inspectData.Config
                        };
                    } catch (error) {
                        this.log('WARN', `Failed to inspect container ${container.id}: ${error.message}`);
                        return {
                            ...container,
                            labels: {},
                            networkSettings: {},
                            config: {}
                        };
                    }
                })
            );
            
            return detailedContainers;
            
        } catch (error) {
            this.log('ERROR', `Failed to get Docker containers: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Check if container is an MCP server
     */
    isMCPServer(container) {
        const labels = container.labels || {};
        return labels['mcp.server'] === 'true';
    }
    
    /**
     * Extract agent information from container
     */
    async extractAgentInfo(container) {
        try {
            const labels = container.labels || {};
            const networkSettings = container.networkSettings || {};
            
            // Extract basic info from labels
            const agentName = labels['mcp.server.name'] || container.names.split(',')[0];
            const agentPort = labels['mcp.server.port'] || '3000';
            const agentProtocol = labels['mcp.server.protocol'] || 'http';
            
            // Determine connection endpoint
            let host = 'localhost';
            let port = agentPort;
            
            // Try to get the mapped port from Docker
            if (container.ports) {
                const portMatch = container.ports.match(new RegExp(`0\\.0\\.0\\.0:(\\d+)->${agentPort}/tcp`));
                if (portMatch) {
                    port = portMatch[1];
                }
            }
            
            // Get internal IP if available
            if (networkSettings.Networks) {
                const networks = Object.values(networkSettings.Networks);
                if (networks.length > 0 && networks[0].IPAddress) {
                    // For internal communication, we might want to use the container IP
                    // But for now, we'll stick with localhost and mapped ports
                }
            }
            
            const agent = {
                id: container.id,
                name: agentName,
                containerId: container.id,
                containerName: container.names,
                image: container.image,
                status: container.status,
                labels: labels,
                connection: {
                    protocol: agentProtocol,
                    host: host,
                    port: parseInt(port),
                    url: `${agentProtocol}://${host}:${port}`
                },
                discoveredAt: new Date().toISOString(),
                lastSeen: new Date().toISOString()
            };
            
            this.log('DEBUG', `Extracted agent info: ${JSON.stringify(agent, null, 2)}`);
            
            return agent;
            
        } catch (error) {
            this.log('ERROR', `Failed to extract agent info: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Get a specific agent by ID
     */
    getAgent(agentId) {
        return this.knownAgents.get(agentId);
    }
    
    /**
     * Get all known agents
     */
    getAllAgents() {
        return Array.from(this.knownAgents.values());
    }
    
    /**
     * Check if Docker is available
     */
    async checkDockerAvailability() {
        try {
            await execAsync('docker version');
            return true;
        } catch (error) {
            this.log('ERROR', `Docker not available: ${error.message}`);
            return false;
        }
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Discovery] ${message}`);
    }
    
    /**
     * Get discovery status
     */
    getStatus() {
        return {
            isRunning: !!this.discoveryTimer,
            isDiscovering: this.isDiscovering,
            knownAgentCount: this.knownAgents.size,
            discoveryInterval: this.config.discoveryInterval
        };
    }
}

module.exports = { Discovery };
