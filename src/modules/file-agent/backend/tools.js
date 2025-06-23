/**
 * File Agent Tools Implementation
 * 
 * Implements the five core file operations:
 * - readFile: Read file contents
 * - writeFile: Write content to file
 * - listDirectory: List directory contents
 * - createDirectory: Create directories
 * - deleteFile: Delete files and directories
 */

const fs = require('fs').promises;
const path = require('path');

class FileTools {
    constructor(config = {}) {
        this.config = {
            workingDirectory: config.workingDirectory || '/app/workspace',
            allowedPaths: config.allowedPaths || ['/app/workspace', '/tmp'],
            maxFileSize: config.maxFileSize || 10 * 1024 * 1024, // 10MB
            ...config
        };
        
        this.log('INFO', 'File Tools initialized');
    }
    
    /**
     * Read file contents
     */
    async readFile(args) {
        try {
            const { path: filePath, encoding = 'utf8' } = args;
            
            if (!filePath) {
                throw new Error('File path is required');
            }
            
            // Validate and resolve path
            const resolvedPath = this.validateAndResolvePath(filePath);
            
            // Check if file exists and is readable
            await fs.access(resolvedPath, fs.constants.R_OK);
            
            // Get file stats
            const stats = await fs.stat(resolvedPath);
            
            if (!stats.isFile()) {
                throw new Error(`Path is not a file: ${filePath}`);
            }
            
            // Check file size
            if (stats.size > this.config.maxFileSize) {
                throw new Error(`File too large: ${stats.size} bytes (max: ${this.config.maxFileSize})`);
            }
            
            // Read file content
            const content = await fs.readFile(resolvedPath, encoding);
            
            this.log('INFO', `Read file: ${filePath} (${stats.size} bytes)`);
            
            return {
                content: content,
                size: stats.size,
                encoding: encoding,
                path: filePath,
                lastModified: stats.mtime.toISOString()
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to read file ${args.path}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Write content to file
     */
    async writeFile(args) {
        try {
            const { path: filePath, content, encoding = 'utf8', createDirectories = false } = args;
            
            if (!filePath) {
                throw new Error('File path is required');
            }
            
            if (content === undefined || content === null) {
                throw new Error('Content is required');
            }
            
            // Validate and resolve path
            const resolvedPath = this.validateAndResolvePath(filePath);
            
            // Create parent directories if requested
            if (createDirectories) {
                const parentDir = path.dirname(resolvedPath);
                await fs.mkdir(parentDir, { recursive: true });
            }
            
            // Write file content
            await fs.writeFile(resolvedPath, content, encoding);
            
            // Get file stats
            const stats = await fs.stat(resolvedPath);
            
            this.log('INFO', `Wrote file: ${filePath} (${stats.size} bytes)`);
            
            return {
                path: filePath,
                size: stats.size,
                encoding: encoding,
                created: stats.birthtime.toISOString(),
                lastModified: stats.mtime.toISOString()
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to write file ${args.path}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * List directory contents
     */
    async listDirectory(args) {
        try {
            const { path: dirPath, recursive = false, includeHidden = false } = args;
            
            if (!dirPath) {
                throw new Error('Directory path is required');
            }
            
            // Validate and resolve path
            const resolvedPath = this.validateAndResolvePath(dirPath);
            
            // Check if directory exists and is readable
            await fs.access(resolvedPath, fs.constants.R_OK);
            
            // Get directory stats
            const stats = await fs.stat(resolvedPath);
            
            if (!stats.isDirectory()) {
                throw new Error(`Path is not a directory: ${dirPath}`);
            }
            
            // List directory contents
            const items = await this.listDirectoryRecursive(resolvedPath, recursive, includeHidden);
            
            this.log('INFO', `Listed directory: ${dirPath} (${items.length} items)`);
            
            return {
                path: dirPath,
                items: items,
                count: items.length,
                recursive: recursive,
                includeHidden: includeHidden
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to list directory ${args.path}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Create directory
     */
    async createDirectory(args) {
        try {
            const { path: dirPath, recursive = false } = args;
            
            if (!dirPath) {
                throw new Error('Directory path is required');
            }
            
            // Validate and resolve path
            const resolvedPath = this.validateAndResolvePath(dirPath);
            
            // Create directory
            await fs.mkdir(resolvedPath, { recursive: recursive });
            
            // Get directory stats
            const stats = await fs.stat(resolvedPath);
            
            this.log('INFO', `Created directory: ${dirPath}`);
            
            return {
                path: dirPath,
                created: stats.birthtime.toISOString(),
                recursive: recursive
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to create directory ${args.path}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Delete file or directory
     */
    async deleteFile(args) {
        try {
            const { path: targetPath, recursive = false, force = false } = args;
            
            if (!targetPath) {
                throw new Error('Path is required');
            }
            
            // Validate and resolve path
            const resolvedPath = this.validateAndResolvePath(targetPath);
            
            // Check if path exists
            await fs.access(resolvedPath);
            
            // Get stats to determine if it's a file or directory
            const stats = await fs.stat(resolvedPath);
            
            if (stats.isDirectory()) {
                if (recursive || force) {
                    await fs.rmdir(resolvedPath, { recursive: true });
                } else {
                    // Check if directory is empty
                    const items = await fs.readdir(resolvedPath);
                    if (items.length > 0) {
                        throw new Error('Directory is not empty. Use recursive=true to delete non-empty directories.');
                    }
                    await fs.rmdir(resolvedPath);
                }
            } else {
                await fs.unlink(resolvedPath);
            }
            
            this.log('INFO', `Deleted: ${targetPath} (${stats.isDirectory() ? 'directory' : 'file'})`);
            
            return {
                path: targetPath,
                type: stats.isDirectory() ? 'directory' : 'file',
                size: stats.size,
                deleted: new Date().toISOString(),
                recursive: recursive,
                force: force
            };
            
        } catch (error) {
            this.log('ERROR', `Failed to delete ${args.path}: ${error.message}`);
            throw error;
        }
    }
    
    /**
     * Validate and resolve file path
     */
    validateAndResolvePath(inputPath) {
        if (!inputPath || typeof inputPath !== 'string') {
            throw new Error('Invalid path');
        }
        
        // Resolve relative paths against working directory
        let resolvedPath;
        if (path.isAbsolute(inputPath)) {
            resolvedPath = path.normalize(inputPath);
        } else {
            resolvedPath = path.resolve(this.config.workingDirectory, inputPath);
        }
        
        // Check if path is within allowed paths
        const isAllowed = this.config.allowedPaths.some(allowedPath => {
            const normalizedAllowed = path.normalize(allowedPath);
            return resolvedPath.startsWith(normalizedAllowed);
        });
        
        if (!isAllowed) {
            throw new Error(`Access denied: Path outside allowed directories: ${inputPath}`);
        }
        
        return resolvedPath;
    }
    
    /**
     * List directory contents recursively
     */
    async listDirectoryRecursive(dirPath, recursive, includeHidden, basePath = '') {
        const items = [];
        
        try {
            const entries = await fs.readdir(dirPath, { withFileTypes: true });
            
            for (const entry of entries) {
                // Skip hidden files if not requested
                if (!includeHidden && entry.name.startsWith('.')) {
                    continue;
                }
                
                const fullPath = path.join(dirPath, entry.name);
                const relativePath = path.join(basePath, entry.name);
                
                try {
                    const stats = await fs.stat(fullPath);
                    
                    const item = {
                        name: entry.name,
                        path: relativePath,
                        type: entry.isDirectory() ? 'directory' : 'file',
                        size: stats.size,
                        lastModified: stats.mtime.toISOString(),
                        permissions: stats.mode
                    };
                    
                    items.push(item);
                    
                    // Recurse into subdirectories if requested
                    if (recursive && entry.isDirectory()) {
                        const subItems = await this.listDirectoryRecursive(
                            fullPath, 
                            recursive, 
                            includeHidden, 
                            relativePath
                        );
                        items.push(...subItems);
                    }
                    
                } catch (error) {
                    // Skip items that can't be accessed
                    this.log('WARN', `Skipping inaccessible item: ${fullPath}`);
                }
            }
            
        } catch (error) {
            throw new Error(`Failed to read directory: ${error.message}`);
        }
        
        return items;
    }
    
    /**
     * Logging utility
     */
    log(level, message) {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${level}] [FileTools] ${message}`);
    }
}

module.exports = { FileTools };
