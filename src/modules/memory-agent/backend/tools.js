/**
 * Memory Agent Tools Implementation
 * Simple in-memory graph-based knowledge storage
 */

const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');

class MemoryTools {
    constructor(config = {}) {
        this.config = {
            dataDirectory: config.dataDirectory || '/app/data',
            maxKnowledgeItems: config.maxKnowledgeItems || 10000,
            ...config
        };
        
        this.knowledge = new Map();
        this.relationships = new Map();
        this.initialized = false;
        
        this.log('INFO', 'Memory Tools initialized');
    }
    
    async initialize() {
        try {
            await this.ensureDataDirectory();
            await this.loadPersistedData();
            this.initialized = true;
            this.log('INFO', 'Memory Tools ready');
        } catch (error) {
            this.log('ERROR', `Failed to initialize: ${error.message}`);
            throw error;
        }
    }
    
    async storeKnowledge(args) {
        try {
            const { key, content, metadata = {}, ttl } = args;
            
            if (!key || !content) {
                throw new Error('Key and content are required');
            }
            
            const knowledgeItem = {
                key,
                content,
                metadata: {
                    ...metadata,
                    created: new Date().toISOString(),
                    updated: new Date().toISOString()
                },
                ttl: ttl ? Date.now() + (ttl * 1000) : null
            };
            
            this.knowledge.set(key, knowledgeItem);
            await this.persistData();
            
            this.log('INFO', `Stored knowledge: ${key}`);
            
            return {
                key,
                stored: true,
                timestamp: knowledgeItem.metadata.created
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to store knowledge: ${error.message}`);
            throw error;
        }
    }
    
    async queryKnowledge(args) {
        try {
            const { query, type = 'fuzzy', limit = 10, includeMetadata = true } = args;
            
            if (!query) {
                throw new Error('Query is required');
            }
            
            let results = [];
            
            // Clean up expired items
            this.cleanupExpiredItems();
            
            if (type === 'exact') {
                const item = this.knowledge.get(query);
                if (item) {
                    results = [this.formatKnowledgeItem(item, includeMetadata)];
                }
            } else {
                // Fuzzy search
                const queryLower = query.toLowerCase();
                for (const [key, item] of this.knowledge) {
                    if (key.toLowerCase().includes(queryLower) || 
                        item.content.toLowerCase().includes(queryLower)) {
                        results.push(this.formatKnowledgeItem(item, includeMetadata));
                    }
                }
            }
            
            // Limit results
            results = results.slice(0, limit);
            
            this.log('INFO', `Query "${query}" returned ${results.length} results`);
            
            return {
                query,
                type,
                results,
                count: results.length,
                timestamp: new Date().toISOString()
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to query knowledge: ${error.message}`);
            throw error;
        }
    }
    
    async createRelationship(args) {
        try {
            const { fromKey, toKey, relationshipType, strength = 0.5, metadata = {} } = args;
            
            if (!fromKey || !toKey || !relationshipType) {
                throw new Error('fromKey, toKey, and relationshipType are required');
            }
            
            // Verify both knowledge items exist
            if (!this.knowledge.has(fromKey)) {
                throw new Error(`Source knowledge item not found: ${fromKey}`);
            }
            if (!this.knowledge.has(toKey)) {
                throw new Error(`Target knowledge item not found: ${toKey}`);
            }
            
            const relationshipId = `${fromKey}->${toKey}:${relationshipType}`;
            const relationship = {
                id: relationshipId,
                fromKey,
                toKey,
                relationshipType,
                strength,
                metadata: {
                    ...metadata,
                    created: new Date().toISOString()
                }
            };
            
            this.relationships.set(relationshipId, relationship);
            await this.persistData();
            
            this.log('INFO', `Created relationship: ${relationshipId}`);
            
            return {
                relationshipId,
                fromKey,
                toKey,
                relationshipType,
                strength,
                created: relationship.metadata.created
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to create relationship: ${error.message}`);
            throw error;
        }
    }
    
    async getContext(args) {
        try {
            const { key, depth = 2, includeContent = true } = args;
            
            if (!key) {
                throw new Error('Key is required');
            }
            
            const rootItem = this.knowledge.get(key);
            if (!rootItem) {
                throw new Error(`Knowledge item not found: ${key}`);
            }
            
            const context = {
                root: this.formatKnowledgeItem(rootItem, true),
                related: this.getRelatedItems(key, depth, includeContent),
                depth,
                timestamp: new Date().toISOString()
            };
            
            this.log('INFO', `Retrieved context for: ${key} (depth: ${depth})`);
            
            return context;
            
        } catch (error) {
            this.log('ERROR', `Failed to get context: ${error.message}`);
            throw error;
        }
    }
    
    getRelatedItems(key, depth, includeContent, visited = new Set()) {
        if (depth <= 0 || visited.has(key)) {
            return [];
        }
        
        visited.add(key);
        const related = [];
        
        // Find direct relationships
        for (const [relationshipId, relationship] of this.relationships) {
            let relatedKey = null;
            let direction = null;
            
            if (relationship.fromKey === key) {
                relatedKey = relationship.toKey;
                direction = 'outgoing';
            } else if (relationship.toKey === key) {
                relatedKey = relationship.fromKey;
                direction = 'incoming';
            }
            
            if (relatedKey && this.knowledge.has(relatedKey)) {
                const relatedItem = {
                    key: relatedKey,
                    relationship: {
                        type: relationship.relationshipType,
                        strength: relationship.strength,
                        direction
                    }
                };
                
                if (includeContent) {
                    relatedItem.content = this.knowledge.get(relatedKey).content;
                    relatedItem.metadata = this.knowledge.get(relatedKey).metadata;
                }
                
                // Recursively get related items
                if (depth > 1) {
                    relatedItem.related = this.getRelatedItems(relatedKey, depth - 1, includeContent, visited);
                }
                
                related.push(relatedItem);
            }
        }
        
        return related;
    }
    
    formatKnowledgeItem(item, includeMetadata) {
        const formatted = {
            key: item.key,
            content: item.content
        };
        
        if (includeMetadata) {
            formatted.metadata = item.metadata;
        }
        
        return formatted;
    }
    
    cleanupExpiredItems() {
        const now = Date.now();
        for (const [key, item] of this.knowledge) {
            if (item.ttl && item.ttl < now) {
                this.knowledge.delete(key);
                // Also remove related relationships
                for (const [relationshipId, relationship] of this.relationships) {
                    if (relationship.fromKey === key || relationship.toKey === key) {
                        this.relationships.delete(relationshipId);
                    }
                }
            }
        }
    }
    
    async getKnowledgeCount() {
        this.cleanupExpiredItems();
        return this.knowledge.size;
    }
    
    async ensureDataDirectory() {
        try {
            await fs.access(this.config.dataDirectory);
        } catch (error) {
            await fs.mkdir(this.config.dataDirectory, { recursive: true });
        }
    }
    
    async persistData() {
        try {
            const data = {
                knowledge: Array.from(this.knowledge.entries()),
                relationships: Array.from(this.relationships.entries()),
                timestamp: new Date().toISOString()
            };
            
            const dataPath = path.join(this.config.dataDirectory, 'memory.json');
            await fs.writeFile(dataPath, JSON.stringify(data, null, 2));
            
        } catch (error) {
            this.log('WARN', `Failed to persist data: ${error.message}`);
        }
    }
    
    async loadPersistedData() {
        try {
            const dataPath = path.join(this.config.dataDirectory, 'memory.json');
            const data = JSON.parse(await fs.readFile(dataPath, 'utf8'));
            
            this.knowledge = new Map(data.knowledge || []);
            this.relationships = new Map(data.relationships || []);
            
            this.log('INFO', `Loaded ${this.knowledge.size} knowledge items and ${this.relationships.size} relationships`);
            
        } catch (error) {
            this.log('INFO', 'No persisted data found, starting fresh');
        }
    }
    
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [MemoryTools] ${message}`);
    }
}

module.exports = { MemoryTools };
