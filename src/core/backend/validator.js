/**
 * Request/Response Validator
 * 
 * Validates MCP-compliant JSON-RPC structure and rejects invalid requests
 * Ensures protocol compliance and data integrity
 */

class Validator {
    constructor(config = {}) {
        this.config = {
            strictMode: config.strictMode !== false, // Default to strict mode
            allowedMethods: config.allowedMethods || [
                'initialize',
                'tools/list',
                'tools/call',
                'ping'
            ],
            ...config
        };
        
        this.log('INFO', 'Request/Response Validator initialized');
    }
    
    /**
     * Validate JSON-RPC request structure
     */
    validateRequest(request) {
        try {
            // Check if request is an object
            if (!request || typeof request !== 'object') {
                return {
                    valid: false,
                    error: 'Request must be a JSON object'
                };
            }
            
            // Validate JSON-RPC version
            if (request.jsonrpc !== '2.0') {
                return {
                    valid: false,
                    error: 'Invalid JSON-RPC version. Must be "2.0"'
                };
            }
            
            // Validate method
            if (!request.method || typeof request.method !== 'string') {
                return {
                    valid: false,
                    error: 'Method must be a non-empty string'
                };
            }
            
            // Check if method is allowed
            if (this.config.strictMode && !this.config.allowedMethods.includes(request.method)) {
                return {
                    valid: false,
                    error: `Method "${request.method}" is not allowed`
                };
            }
            
            // Validate ID (must be present for requests)
            if (request.id === undefined || request.id === null) {
                return {
                    valid: false,
                    error: 'Request ID is required'
                };
            }
            
            // Validate params (optional, but if present must be object or array)
            if (request.params !== undefined) {
                if (typeof request.params !== 'object') {
                    return {
                        valid: false,
                        error: 'Params must be an object or array'
                    };
                }
            }
            
            return { valid: true };
            
        } catch (error) {
            return {
                valid: false,
                error: `Validation error: ${error.message}`
            };
        }
    }
    
    /**
     * Validate JSON-RPC response structure
     */
    validateResponse(response) {
        try {
            // Check if response is an object
            if (!response || typeof response !== 'object') {
                return {
                    valid: false,
                    error: 'Response must be a JSON object'
                };
            }
            
            // Validate JSON-RPC version
            if (response.jsonrpc !== '2.0') {
                return {
                    valid: false,
                    error: 'Invalid JSON-RPC version. Must be "2.0"'
                };
            }
            
            // Validate ID
            if (response.id === undefined || response.id === null) {
                return {
                    valid: false,
                    error: 'Response ID is required'
                };
            }
            
            // Must have either result or error, but not both
            const hasResult = response.result !== undefined;
            const hasError = response.error !== undefined;
            
            if (!hasResult && !hasError) {
                return {
                    valid: false,
                    error: 'Response must have either result or error'
                };
            }
            
            if (hasResult && hasError) {
                return {
                    valid: false,
                    error: 'Response cannot have both result and error'
                };
            }
            
            // Validate error structure if present
            if (hasError) {
                const errorValidation = this.validateError(response.error);
                if (!errorValidation.valid) {
                    return errorValidation;
                }
            }
            
            return { valid: true };
            
        } catch (error) {
            return {
                valid: false,
                error: `Response validation error: ${error.message}`
            };
        }
    }
    
    /**
     * Validate error object structure
     */
    validateError(error) {
        if (!error || typeof error !== 'object') {
            return {
                valid: false,
                error: 'Error must be an object'
            };
        }
        
        // Validate error code
        if (typeof error.code !== 'number') {
            return {
                valid: false,
                error: 'Error code must be a number'
            };
        }
        
        // Validate error message
        if (!error.message || typeof error.message !== 'string') {
            return {
                valid: false,
                error: 'Error message must be a non-empty string'
            };
        }
        
        return { valid: true };
    }
    
    /**
     * Validate initialize request parameters
     */
    validateInitialize(params) {
        try {
            if (!params) {
                params = {};
            }
            
            // protocolVersion is optional but if present must be string
            if (params.protocolVersion !== undefined && typeof params.protocolVersion !== 'string') {
                return {
                    valid: false,
                    error: 'protocolVersion must be a string'
                };
            }
            
            // capabilities is optional but if present must be object
            if (params.capabilities !== undefined && typeof params.capabilities !== 'object') {
                return {
                    valid: false,
                    error: 'capabilities must be an object'
                };
            }
            
            // clientInfo is optional but if present must be object
            if (params.clientInfo !== undefined && typeof params.clientInfo !== 'object') {
                return {
                    valid: false,
                    error: 'clientInfo must be an object'
                };
            }
            
            return { valid: true };
            
        } catch (error) {
            return {
                valid: false,
                error: `Initialize validation error: ${error.message}`
            };
        }
    }
    
    /**
     * Validate tool call parameters
     */
    validateToolCall(params) {
        try {
            if (!params || typeof params !== 'object') {
                return {
                    valid: false,
                    error: 'Tool call params must be an object'
                };
            }
            
            // Validate tool name
            if (!params.name || typeof params.name !== 'string') {
                return {
                    valid: false,
                    error: 'Tool name must be a non-empty string'
                };
            }
            
            // Validate tool name format (no spaces, special chars)
            if (!/^[a-zA-Z0-9_-]+$/.test(params.name)) {
                return {
                    valid: false,
                    error: 'Tool name must contain only alphanumeric characters, underscores, and hyphens'
                };
            }
            
            // Arguments are optional but if present must be object
            if (params.arguments !== undefined && typeof params.arguments !== 'object') {
                return {
                    valid: false,
                    error: 'Tool arguments must be an object'
                };
            }
            
            return { valid: true };
            
        } catch (error) {
            return {
                valid: false,
                error: `Tool call validation error: ${error.message}`
            };
        }
    }
    
    /**
     * Validate tool definition
     */
    validateToolDefinition(tool) {
        try {
            if (!tool || typeof tool !== 'object') {
                return {
                    valid: false,
                    error: 'Tool definition must be an object'
                };
            }
            
            // Validate name
            if (!tool.name || typeof tool.name !== 'string') {
                return {
                    valid: false,
                    error: 'Tool name must be a non-empty string'
                };
            }
            
            // Validate description
            if (!tool.description || typeof tool.description !== 'string') {
                return {
                    valid: false,
                    error: 'Tool description must be a non-empty string'
                };
            }
            
            // Validate inputSchema
            if (!tool.inputSchema || typeof tool.inputSchema !== 'object') {
                return {
                    valid: false,
                    error: 'Tool inputSchema must be an object'
                };
            }
            
            // Basic JSON Schema validation
            if (tool.inputSchema.type && typeof tool.inputSchema.type !== 'string') {
                return {
                    valid: false,
                    error: 'inputSchema type must be a string'
                };
            }
            
            return { valid: true };
            
        } catch (error) {
            return {
                valid: false,
                error: `Tool definition validation error: ${error.message}`
            };
        }
    }
    
    /**
     * Sanitize input data
     */
    sanitizeInput(data) {
        try {
            // Remove any potentially dangerous properties
            const sanitized = JSON.parse(JSON.stringify(data));
            
            // Remove __proto__ and constructor
            delete sanitized.__proto__;
            delete sanitized.constructor;
            
            return sanitized;
            
        } catch (error) {
            throw new Error(`Failed to sanitize input: ${error.message}`);
        }
    }
    
    /**
     * Create standardized error response
     */
    createErrorResponse(id, code, message, data = null) {
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
        
        return response;
    }
    
    /**
     * Create standardized success response
     */
    createSuccessResponse(id, result) {
        return {
            jsonrpc: '2.0',
            id: id,
            result: result
        };
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [Validator] ${message}`);
    }
    
    /**
     * Get validator status
     */
    getStatus() {
        return {
            strictMode: this.config.strictMode,
            allowedMethods: this.config.allowedMethods
        };
    }
}

module.exports = { Validator };
