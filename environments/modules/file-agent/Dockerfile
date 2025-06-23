# MCP File Agent Container
FROM node:18-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache curl bash

# Create non-root user
RUN addgroup -g 1001 -S mcpuser && \
    adduser -S mcpuser -u 1001 -G mcpuser

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy source code
COPY src/modules/file-agent/ ./src/modules/file-agent/

# Create workspace directory
RUN mkdir -p /app/workspace && chown -R mcpuser:mcpuser /app

# Switch to non-root user
USER mcpuser

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

# Environment variables
ENV NODE_ENV=production
ENV FILE_AGENT_PORT=3001
ENV FILE_AGENT_HOST=0.0.0.0
ENV FILE_AGENT_WORKDIR=/app/workspace

# Labels for MCP discovery
LABEL mcp.server=true
LABEL mcp.server.name=file-agent
LABEL mcp.server.port=3001
LABEL mcp.server.protocol=http

# Start the agent
CMD ["node", "src/modules/file-agent/backend/index.js"]
