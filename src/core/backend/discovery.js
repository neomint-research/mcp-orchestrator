/**
 * Docker-based Agent Discovery
 * 
 * Discovers MCP agent containers using Docker labels and extracts connection data
 * Monitors for container lifecycle events and maintains agent registry
 */

const EventEmitter = require('events');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');

const execAsync = promisify(exec);

class Discovery extends EventEmitter {
    /**
     * Get the current user's UID dynamically
     */
    static async getCurrentUID() {
        try {
            // Try to get UID from environment first (works in containers)
            if (process.env.UID) {
                return parseInt(process.env.UID);
            }

            // Try to get UID from process (works on Unix systems)
            if (process.getuid && typeof process.getuid === 'function') {
                return process.getuid();
            }

            // Fallback: try to execute 'id -u' command
            const { stdout } = await execAsync('id -u');
            return parseInt(stdout.trim());
        } catch (error) {
            // Last resort fallback to common UID
            console.warn(`[Discovery] Could not determine current UID, using fallback 1001: ${error.message}`);
            return 1001;
        }
    }

    /**
     * Get possible rootless Docker socket paths for the current user
     */
    static async getPossibleRootlessSocketPaths() {
        const uid = await this.getCurrentUID();
        const home = process.env.HOME || process.env.USERPROFILE || `/home/${process.env.USER || 'user'}`;

        const paths = [
            // Standard XDG runtime directory (most common)
            `/run/user/${uid}/docker.sock`,
            // Alternative runtime directories
            `/tmp/docker-${uid}/docker.sock`,
            `/var/run/user/${uid}/docker.sock`,
            // User home directory locations
            `${home}/.docker/run/docker.sock`,
            `${home}/.docker/desktop/docker.sock`,
            // Environment variable override
            process.env.DOCKER_HOST ? process.env.DOCKER_HOST.replace('unix://', '') : null,
            // Explicit environment variable for rootless socket
            process.env.DOCKER_ROOTLESS_SOCKET_PATH
        ].filter(Boolean); // Remove null/undefined entries

        // Filter to only existing and accessible paths
        const validPaths = [];
        for (const socketPath of paths) {
            try {
                if (fs.existsSync(socketPath)) {
                    // Check if it's actually a socket
                    const stats = fs.statSync(socketPath);
                    if (stats.isSocket()) {
                        validPaths.push(socketPath);
                    }
                }
            } catch (error) {
                // Ignore access errors, path doesn't exist or no permission
            }
        }

        // If no valid sockets found, return the most likely paths for testing
        return validPaths.length > 0 ? validPaths : [
            `/run/user/${uid}/docker.sock`,
            `/tmp/docker-${uid}/docker.sock`
        ];
    }

    /**
     * Get the default rootless socket path for the current user
     */
    getDefaultRootlessSocketPath() {
        // This is a synchronous fallback - we'll use async detection in detectDockerMode
        const uid = process.env.UID || '1001'; // Use env UID or fallback
        return `/run/user/${uid}/docker.sock`;
    }

    /**
     * Validate Docker socket connectivity
     */
    static async validateDockerSocket(socketPath) {
        try {
            // Check if socket file exists and is accessible
            if (!fs.existsSync(socketPath)) {
                return { valid: false, reason: 'Socket file does not exist' };
            }

            const stats = fs.statSync(socketPath);
            if (!stats.isSocket()) {
                return { valid: false, reason: 'Path exists but is not a socket' };
            }

            // Try a simple Docker command to test connectivity
            const testEnv = { ...process.env, DOCKER_HOST: `unix://${socketPath}` };
            await execAsync('docker version --format "{{.Server.Version}}"', { env: testEnv, timeout: 5000 });

            return { valid: true, reason: 'Socket is accessible and Docker responds' };
        } catch (error) {
            return { valid: false, reason: `Docker command failed: ${error.message}` };
        }
    }
    constructor(config = {}) {
        super();

        this.config = {
            discoveryInterval: config.discoveryInterval || 30000,
            dockerRootlessSocket: config.dockerRootlessSocket || process.env.DOCKER_ROOTLESS_SOCKET_PATH || this.getDefaultRootlessSocketPath(),
            dockerMode: 'rootless', // Force rootless mode - no fallback to standard Docker
            retryAttempts: config.retryAttempts || parseInt(process.env.DISCOVERY_RETRY_ATTEMPTS) || 10,
            retryDelay: config.retryDelay || parseInt(process.env.DISCOVERY_RETRY_DELAY) || 3000,
            labelFilter: config.labelFilter || 'mcp.server=true',
            ...config
        };

        this.knownAgents = new Map();
        this.discoveryTimer = null;
        this.isDiscovering = false;
        this.dockerMode = null; // Will be determined at runtime
        this.dockerHost = null; // Will be set based on detected mode

        this.log('INFO', 'Docker Discovery initialized');
    }
    
    /**
     * Start continuous agent discovery
     */
    async startDiscovery() {
        if (this.discoveryTimer) {
            this.log('WARN', 'Discovery already running');
            return;
        }

        this.log('INFO', 'Starting continuous agent discovery');

        // Detect Docker mode first
        await this.detectDockerMode();

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

            // Detect Docker mode if not already detected
            if (!this.dockerMode) {
                await this.detectDockerMode();
            }
            
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
            const { stdout } = await this.executeDockerCommandWithRetry(command);

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
                        const env = { ...process.env };
                        if (this.dockerHost) {
                            env.DOCKER_HOST = this.dockerHost;
                        }

                        const inspectCommand = `docker inspect ${container.id}`;
                        const { stdout: inspectOutput } = await this.executeDockerCommandWithRetry(inspectCommand, env);
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
     * Execute Docker command with retry logic for rootless Docker only
     */
    async executeDockerCommandWithRetry(command, env = process.env, attempt = 1) {
        // Ensure rootless Docker mode is detected
        if (!this.dockerMode) {
            await this.detectDockerMode();
        }

        try {
            // Use rootless Docker configuration
            const finalEnv = { ...env };
            if (this.dockerHost) {
                finalEnv.DOCKER_HOST = this.dockerHost;
            }

            const { stdout, stderr } = await execAsync(command, { env: finalEnv });
            return { stdout, stderr };
        } catch (error) {
            if (attempt < this.config.retryAttempts) {
                this.log('WARN', `Rootless Docker command failed (attempt ${attempt}/${this.config.retryAttempts}): ${error.message}`);
                await this.sleep(this.config.retryDelay * attempt); // Exponential backoff

                // Use rootless Docker configuration for retry
                const retryEnv = { ...env };
                if (this.dockerHost) {
                    retryEnv.DOCKER_HOST = this.dockerHost;
                }

                return this.executeDockerCommandWithRetry(command, retryEnv, attempt + 1);
            } else {
                this.log('ERROR', `Rootless Docker command failed after ${this.config.retryAttempts} attempts: ${error.message}`);
                throw error;
            }
        }
    }

    /**
     * Sleep utility for retry delays
     */
    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Detect rootless Docker mode and socket paths
     */
    async detectDockerMode() {
        this.dockerMode = 'rootless'; // Force rootless mode
        this.log('INFO', 'Initializing rootless Docker mode...');

        // Get all possible rootless Docker socket paths
        const possibleRootlessPaths = await Discovery.getPossibleRootlessSocketPaths();
        this.log('DEBUG', `Checking rootless Docker socket paths: ${possibleRootlessPaths.join(', ')}`);

        for (const rootlessSocketPath of possibleRootlessPaths) {
            this.log('DEBUG', `Testing rootless Docker socket: ${rootlessSocketPath}`);
            const validation = await Discovery.validateDockerSocket(rootlessSocketPath);

            if (validation.valid) {
                this.dockerHost = `unix://${rootlessSocketPath}`;
                this.log('INFO', `Found rootless Docker at: ${rootlessSocketPath} (${validation.reason})`);
                return;
            } else {
                this.log('DEBUG', `Rootless Docker socket invalid at ${rootlessSocketPath}: ${validation.reason}`);
            }
        }

        // If no socket found, throw error - no fallback to standard Docker
        this.log('ERROR', 'No accessible rootless Docker sockets found');
        throw new Error('Rootless Docker is not available. Please ensure rootless Docker is installed and running. See: https://docs.docker.com/engine/security/rootless/');
    }

    /**
     * Check if Docker is available
     */
    async checkDockerAvailability() {
        try {
            await this.detectDockerMode();
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
