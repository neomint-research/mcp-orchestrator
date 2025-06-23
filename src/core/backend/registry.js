/**
 * Runtime Registry & Module Status Management
 * 
 * Manages plugin registry and module status tracking for the MCP orchestrator
 * Provides persistent storage of discovered modules and their health status
 */

const fs = require('fs').promises;
const path = require('path');

class RegistryManager {
    constructor(config = {}) {
        this.config = {
            registryPath: config.registryPath || process.env.REGISTRY_PATH || './registry',
            pluginsFile: config.pluginsFile || 'plugins.json',
            statusFile: config.statusFile || 'module-status.json',
            errorLogFile: config.errorLogFile || 'error-log.json',
            maxErrorLogEntries: config.maxErrorLogEntries || 1000,
            ...config
        };
        
        this.plugins = new Map();
        this.moduleStatus = new Map();
        this.errorLog = [];
        this.initialized = false;
        
        this.log('INFO', 'Registry Manager initialized');
    }
    
    /**
     * Initialize the registry system
     */
    async initialize() {
        try {
            await this.ensureRegistryDirectory();
            await this.loadPersistedData();
            this.initialized = true;
            this.log('INFO', 'Registry Manager ready');
        } catch (error) {
            this.log('ERROR', `Failed to initialize registry: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Register a discovered plugin/agent
     */
    async registerPlugin(agentConfig, tools = []) {
        try {
            const plugin = {
                id: agentConfig.id,
                name: agentConfig.name,
                containerId: agentConfig.containerId,
                containerName: agentConfig.containerName,
                image: agentConfig.image,
                connection: agentConfig.connection,
                tools: tools.map(tool => ({
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema
                })),
                labels: agentConfig.labels || {},
                registeredAt: new Date().toISOString(),
                lastSeen: new Date().toISOString(),
                status: 'active'
            };
            
            this.plugins.set(agentConfig.id, plugin);
            
            // Initialize module status
            this.moduleStatus.set(agentConfig.id, {
                agentId: agentConfig.id,
                name: agentConfig.name,
                status: 'active',
                lastHealthCheck: new Date().toISOString(),
                successCount: 0,
                failureCount: 0,
                lastSuccess: null,
                lastFailure: null,
                averageResponseTime: 0,
                uptime: 0
            });
            
            await this.persistData();
            
            this.log('INFO', `Registered plugin: ${agentConfig.name} with ${tools.length} tools`);
            
            return plugin;
            
        } catch (error) {
            this.log('ERROR', `Failed to register plugin ${agentConfig.name}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Update plugin status
     */
    async updatePluginStatus(agentId, status, metadata = {}) {
        try {
            const plugin = this.plugins.get(agentId);
            if (!plugin) {
                throw new Error(`Plugin not found: ${agentId}`);
            }
            
            plugin.status = status;
            plugin.lastSeen = new Date().toISOString();
            
            if (metadata) {
                plugin.metadata = { ...plugin.metadata, ...metadata };
            }
            
            this.plugins.set(agentId, plugin);
            await this.persistData();
            
            this.log('INFO', `Updated plugin status: ${plugin.name} -> ${status}`);
            
        } catch (error) {
            this.log('ERROR', `Failed to update plugin status: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Record module health status
     */
    async recordModuleHealth(agentId, success, responseTime = 0, error = null) {
        try {
            let status = this.moduleStatus.get(agentId);
            if (!status) {
                // Create new status entry
                const plugin = this.plugins.get(agentId);
                status = {
                    agentId: agentId,
                    name: plugin ? plugin.name : agentId,
                    status: 'unknown',
                    lastHealthCheck: new Date().toISOString(),
                    successCount: 0,
                    failureCount: 0,
                    lastSuccess: null,
                    lastFailure: null,
                    averageResponseTime: 0,
                    uptime: 0
                };
            }
            
            const now = new Date().toISOString();
            status.lastHealthCheck = now;
            
            if (success) {
                status.successCount++;
                status.lastSuccess = now;
                status.status = 'healthy';
                
                // Update average response time
                if (status.averageResponseTime === 0) {
                    status.averageResponseTime = responseTime;
                } else {
                    status.averageResponseTime = (status.averageResponseTime + responseTime) / 2;
                }
                
            } else {
                status.failureCount++;
                status.lastFailure = now;
                status.status = 'unhealthy';
                
                // Log error if provided
                if (error) {
                    await this.logError(agentId, 'health_check', error);
                }
            }
            
            // Calculate uptime percentage
            const totalChecks = status.successCount + status.failureCount;
            status.uptime = totalChecks > 0 ? (status.successCount / totalChecks) * 100 : 0;
            
            this.moduleStatus.set(agentId, status);
            await this.persistData();
            
        } catch (error) {
            this.log('ERROR', `Failed to record module health: ${error.message}`);
        }
    }
    
    /**
     * Log an error
     */
    async logError(agentId, tool, error, correlationId = null) {
        try {
            const errorEntry = {
                timestamp: new Date().toISOString(),
                agentId: agentId,
                tool: tool,
                error_code: error.code || -1,
                message: error.message || error.toString(),
                correlation_id: correlationId || this.generateCorrelationId(),
                stack: error.stack || null
            };
            
            this.errorLog.push(errorEntry);
            
            // Limit error log size
            if (this.errorLog.length > this.config.maxErrorLogEntries) {
                this.errorLog = this.errorLog.slice(-this.config.maxErrorLogEntries);
            }
            
            await this.persistErrorLog();
            
            this.log('WARN', `Logged error for ${agentId}:${tool} - ${error.message}`);
            
        } catch (err) {
            this.log('ERROR', `Failed to log error: ${err.message}`);
        }
    }
    
    /**
     * Get plugin registry
     */
    getPlugins() {
        return Array.from(this.plugins.values());
    }
    
    /**
     * Get plugin by ID
     */
    getPlugin(agentId) {
        return this.plugins.get(agentId);
    }
    
    /**
     * Get module status
     */
    getModuleStatus(agentId = null) {
        if (agentId) {
            return this.moduleStatus.get(agentId);
        }
        return Array.from(this.moduleStatus.values());
    }
    
    /**
     * Get error log
     */
    getErrorLog(agentId = null, limit = 100) {
        let errors = this.errorLog;
        
        if (agentId) {
            errors = errors.filter(error => error.agentId === agentId);
        }
        
        return errors.slice(-limit);
    }
    
    /**
     * Get registry statistics
     */
    getStatistics() {
        const plugins = this.getPlugins();
        const statuses = this.getModuleStatus();
        
        const stats = {
            totalPlugins: plugins.length,
            activePlugins: plugins.filter(p => p.status === 'active').length,
            totalTools: plugins.reduce((sum, p) => sum + p.tools.length, 0),
            healthyModules: statuses.filter(s => s.status === 'healthy').length,
            unhealthyModules: statuses.filter(s => s.status === 'unhealthy').length,
            averageUptime: statuses.length > 0 ? 
                statuses.reduce((sum, s) => sum + s.uptime, 0) / statuses.length : 0,
            totalErrors: this.errorLog.length,
            lastUpdate: new Date().toISOString()
        };
        
        return stats;
    }
    
    /**
     * Remove plugin from registry
     */
    async removePlugin(agentId) {
        try {
            const plugin = this.plugins.get(agentId);
            if (!plugin) {
                return false;
            }
            
            this.plugins.delete(agentId);
            this.moduleStatus.delete(agentId);
            
            await this.persistData();
            
            this.log('INFO', `Removed plugin: ${plugin.name}`);
            return true;
            
        } catch (error) {
            this.log('ERROR', `Failed to remove plugin: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Ensure registry directory exists
     */
    async ensureRegistryDirectory() {
        try {
            await fs.access(this.config.registryPath);
        } catch (error) {
            await fs.mkdir(this.config.registryPath, { recursive: true });
            this.log('INFO', `Created registry directory: ${this.config.registryPath}`);
        }
    }
    
    /**
     * Persist registry data
     */
    async persistData() {
        try {
            const pluginsData = {
                plugins: Array.from(this.plugins.entries()),
                timestamp: new Date().toISOString()
            };
            
            const statusData = {
                moduleStatus: Array.from(this.moduleStatus.entries()),
                timestamp: new Date().toISOString()
            };
            
            const pluginsPath = path.join(this.config.registryPath, this.config.pluginsFile);
            const statusPath = path.join(this.config.registryPath, this.config.statusFile);
            
            await Promise.all([
                fs.writeFile(pluginsPath, JSON.stringify(pluginsData, null, 2)),
                fs.writeFile(statusPath, JSON.stringify(statusData, null, 2))
            ]);
            
        } catch (error) {
            this.log('WARN', `Failed to persist registry data: ${error.message}`);
        }
    }
    
    /**
     * Persist error log
     */
    async persistErrorLog() {
        try {
            const errorLogData = {
                errors: this.errorLog,
                timestamp: new Date().toISOString()
            };
            
            const errorLogPath = path.join(this.config.registryPath, this.config.errorLogFile);
            await fs.writeFile(errorLogPath, JSON.stringify(errorLogData, null, 2));
            
        } catch (error) {
            this.log('WARN', `Failed to persist error log: ${error.message}`);
        }
    }
    
    /**
     * Load persisted data
     */
    async loadPersistedData() {
        try {
            const pluginsPath = path.join(this.config.registryPath, this.config.pluginsFile);
            const statusPath = path.join(this.config.registryPath, this.config.statusFile);
            const errorLogPath = path.join(this.config.registryPath, this.config.errorLogFile);
            
            // Load plugins
            try {
                const pluginsData = JSON.parse(await fs.readFile(pluginsPath, 'utf8'));
                this.plugins = new Map(pluginsData.plugins || []);
                this.log('INFO', `Loaded ${this.plugins.size} plugins from registry`);
            } catch (error) {
                this.log('INFO', 'No existing plugins registry found, starting fresh');
            }
            
            // Load module status
            try {
                const statusData = JSON.parse(await fs.readFile(statusPath, 'utf8'));
                this.moduleStatus = new Map(statusData.moduleStatus || []);
                this.log('INFO', `Loaded ${this.moduleStatus.size} module statuses from registry`);
            } catch (error) {
                this.log('INFO', 'No existing module status found, starting fresh');
            }
            
            // Load error log
            try {
                const errorLogData = JSON.parse(await fs.readFile(errorLogPath, 'utf8'));
                this.errorLog = errorLogData.errors || [];
                this.log('INFO', `Loaded ${this.errorLog.length} error log entries`);
            } catch (error) {
                this.log('INFO', 'No existing error log found, starting fresh');
            }
            
        } catch (error) {
            this.log('WARN', `Failed to load persisted data: ${error.message}`);
        }
    }
    
    /**
     * Generate correlation ID
     */
    generateCorrelationId() {
        return `reg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Registry] ${message}`);
    }
    
    /**
     * Get registry status
     */
    getStatus() {
        return {
            initialized: this.initialized,
            pluginCount: this.plugins.size,
            moduleStatusCount: this.moduleStatus.size,
            errorLogCount: this.errorLog.length,
            registryPath: this.config.registryPath,
            statistics: this.getStatistics()
        };
    }
}

module.exports = { RegistryManager };
