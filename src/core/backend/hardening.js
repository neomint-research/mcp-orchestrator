/**
 * Error Handling and Timeout Management
 * 
 * Provides robust error handling, timeout management, and structured error responses
 * Implements circuit breaker pattern and graceful degradation
 */

const EventEmitter = require('events');

class Hardening extends EventEmitter {
    constructor(config = {}) {
        super();
        
        this.config = {
            defaultTimeout: config.defaultTimeout || 30000,
            maxRetries: config.maxRetries || 3,
            retryDelay: config.retryDelay || 1000,
            circuitBreakerThreshold: config.circuitBreakerThreshold || 5,
            circuitBreakerTimeout: config.circuitBreakerTimeout || 60000,
            ...config
        };
        
        // Circuit breaker state for each agent
        this.circuitBreakers = new Map();
        
        // Error tracking
        this.errorStats = new Map();
        
        this.log('INFO', 'Error Hardening initialized');
    }
    
    /**
     * Safe tool call with comprehensive error handling
     */
    async safeToolCall(toolCallFunction, timeout = null, context = {}) {
        const actualTimeout = timeout || this.config.defaultTimeout;
        const startTime = Date.now();
        
        try {
            this.log('DEBUG', `Starting safe tool call with ${actualTimeout}ms timeout`);
            
            // Check circuit breaker
            if (context.agentId && this.isCircuitBreakerOpen(context.agentId)) {
                throw new Error(`Circuit breaker is open for agent ${context.agentId}`);
            }
            
            // Execute with timeout
            const result = await this.executeWithTimeout(toolCallFunction, actualTimeout);
            
            // Record success
            if (context.agentId) {
                this.recordSuccess(context.agentId);
            }
            
            const duration = Date.now() - startTime;
            this.log('DEBUG', `Tool call completed successfully in ${duration}ms`);
            
            return result;
            
        } catch (error) {
            const duration = Date.now() - startTime;
            
            // Record failure
            if (context.agentId) {
                this.recordFailure(context.agentId, error);
            }
            
            this.log('ERROR', `Tool call failed after ${duration}ms: ${error.message}`);
            
            // Create structured error response
            throw this.createStructuredError(error, context);
        }
    }
    
    /**
     * Execute function with timeout
     */
    async executeWithTimeout(fn, timeout) {
        return new Promise(async (resolve, reject) => {
            const timeoutId = setTimeout(() => {
                reject(new Error(`Operation timed out after ${timeout}ms`));
            }, timeout);
            
            try {
                const result = await fn();
                clearTimeout(timeoutId);
                resolve(result);
            } catch (error) {
                clearTimeout(timeoutId);
                reject(error);
            }
        });
    }
    
    /**
     * Safe async operation with retries
     */
    async safeAsyncOperation(operation, options = {}) {
        const {
            maxRetries = this.config.maxRetries,
            retryDelay = this.config.retryDelay,
            timeout = this.config.defaultTimeout,
            context = {}
        } = options;
        
        let lastError;
        
        for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
            try {
                this.log('DEBUG', `Attempt ${attempt}/${maxRetries + 1}`);
                
                const result = await this.safeToolCall(operation, timeout, context);
                
                if (attempt > 1) {
                    this.log('INFO', `Operation succeeded on attempt ${attempt}`);
                }
                
                return result;
                
            } catch (error) {
                lastError = error;
                
                if (attempt <= maxRetries) {
                    const delay = retryDelay * Math.pow(2, attempt - 1); // Exponential backoff
                    this.log('WARN', `Attempt ${attempt} failed, retrying in ${delay}ms: ${error.message}`);
                    await this.delay(delay);
                } else {
                    this.log('ERROR', `All ${maxRetries + 1} attempts failed`);
                }
            }
        }
        
        throw lastError;
    }
    
    /**
     * Create structured error response
     */
    createStructuredError(error, context = {}) {
        const structuredError = new Error(error.message);
        structuredError.name = 'MCPOrchestratorError';
        
        // Determine error code based on error type
        let errorCode = -32603; // Internal error (default)
        
        if (error.message.includes('timeout')) {
            errorCode = -32001; // Timeout error
        } else if (error.message.includes('not found')) {
            errorCode = -32601; // Method not found
        } else if (error.message.includes('invalid')) {
            errorCode = -32602; // Invalid params
        } else if (error.message.includes('parse')) {
            errorCode = -32700; // Parse error
        } else if (error.message.includes('circuit breaker')) {
            errorCode = -32002; // Service unavailable
        }
        
        structuredError.code = errorCode;
        structuredError.data = {
            originalError: error.message,
            timestamp: new Date().toISOString(),
            context: context,
            correlationId: this.generateCorrelationId()
        };
        
        return structuredError;
    }
    
    /**
     * Circuit breaker implementation
     */
    isCircuitBreakerOpen(agentId) {
        const breaker = this.circuitBreakers.get(agentId);
        if (!breaker) {
            return false;
        }
        
        if (breaker.state === 'open') {
            // Check if timeout has passed
            if (Date.now() - breaker.lastFailure > this.config.circuitBreakerTimeout) {
                breaker.state = 'half-open';
                breaker.failureCount = 0;
                this.log('INFO', `Circuit breaker for ${agentId} moved to half-open state`);
            }
            return breaker.state === 'open';
        }
        
        return false;
    }
    
    /**
     * Record successful operation
     */
    recordSuccess(agentId) {
        const breaker = this.circuitBreakers.get(agentId) || this.createCircuitBreaker(agentId);
        
        if (breaker.state === 'half-open') {
            breaker.state = 'closed';
            breaker.failureCount = 0;
            this.log('INFO', `Circuit breaker for ${agentId} closed after successful operation`);
        }
        
        breaker.lastSuccess = Date.now();
        this.circuitBreakers.set(agentId, breaker);
    }
    
    /**
     * Record failed operation
     */
    recordFailure(agentId, error) {
        const breaker = this.circuitBreakers.get(agentId) || this.createCircuitBreaker(agentId);
        
        breaker.failureCount++;
        breaker.lastFailure = Date.now();
        
        if (breaker.failureCount >= this.config.circuitBreakerThreshold) {
            breaker.state = 'open';
            this.log('WARN', `Circuit breaker for ${agentId} opened after ${breaker.failureCount} failures`);
            this.emit('circuitBreakerOpened', { agentId, failureCount: breaker.failureCount });
        }
        
        this.circuitBreakers.set(agentId, breaker);
        
        // Update error statistics
        this.updateErrorStats(agentId, error);
    }
    
    /**
     * Create new circuit breaker
     */
    createCircuitBreaker(agentId) {
        return {
            state: 'closed', // closed, open, half-open
            failureCount: 0,
            lastFailure: null,
            lastSuccess: null
        };
    }
    
    /**
     * Update error statistics
     */
    updateErrorStats(agentId, error) {
        const stats = this.errorStats.get(agentId) || {
            totalErrors: 0,
            errorTypes: new Map(),
            lastError: null,
            firstError: null
        };
        
        stats.totalErrors++;
        stats.lastError = {
            message: error.message,
            timestamp: new Date().toISOString()
        };
        
        if (!stats.firstError) {
            stats.firstError = stats.lastError;
        }
        
        // Track error types
        const errorType = this.categorizeError(error);
        const typeCount = stats.errorTypes.get(errorType) || 0;
        stats.errorTypes.set(errorType, typeCount + 1);
        
        this.errorStats.set(agentId, stats);
    }
    
    /**
     * Categorize error type
     */
    categorizeError(error) {
        const message = error.message.toLowerCase();
        
        if (message.includes('timeout')) return 'timeout';
        if (message.includes('connection')) return 'connection';
        if (message.includes('parse')) return 'parse';
        if (message.includes('validation')) return 'validation';
        if (message.includes('not found')) return 'not_found';
        
        return 'unknown';
    }
    
    /**
     * Generate correlation ID for error tracking
     */
    generateCorrelationId() {
        return `err_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }
    
    /**
     * Delay utility
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
    
    /**
     * Get error statistics
     */
    getErrorStats(agentId = null) {
        if (agentId) {
            return this.errorStats.get(agentId) || null;
        }
        
        const allStats = {};
        for (const [id, stats] of this.errorStats) {
            allStats[id] = {
                ...stats,
                errorTypes: Object.fromEntries(stats.errorTypes)
            };
        }
        
        return allStats;
    }
    
    /**
     * Get circuit breaker status
     */
    getCircuitBreakerStatus(agentId = null) {
        if (agentId) {
            return this.circuitBreakers.get(agentId) || null;
        }
        
        return Object.fromEntries(this.circuitBreakers);
    }
    
    /**
     * Reset circuit breaker
     */
    resetCircuitBreaker(agentId) {
        const breaker = this.createCircuitBreaker(agentId);
        this.circuitBreakers.set(agentId, breaker);
        this.log('INFO', `Circuit breaker for ${agentId} has been reset`);
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Hardening] ${message}`);
    }
    
    /**
     * Get hardening status
     */
    getStatus() {
        return {
            config: this.config,
            circuitBreakers: this.getCircuitBreakerStatus(),
            errorStats: this.getErrorStats(),
            activeBreakers: Array.from(this.circuitBreakers.entries())
                .filter(([_, breaker]) => breaker.state !== 'closed')
                .map(([agentId, breaker]) => ({ agentId, state: breaker.state }))
        };
    }
}

module.exports = { Hardening };
