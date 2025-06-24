# MCP Multi-Agent Orchestrator - Core Container
# Base image with Node.js 18 LTS
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    docker-cli \
    curl \
    bash

# Create non-root user for rootless Docker operation
# Support dynamic UID through build args for user namespace mapping
ARG USER_ID=1001
ARG GROUP_ID=1001

RUN addgroup -g ${GROUP_ID} -S mcpuser && \
    adduser -S mcpuser -u ${USER_ID} -G mcpuser

# Copy package files first for better caching
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy source code
COPY src/core/ ./src/core/
COPY scripts/ ./scripts/

# Create entrypoint script for dynamic permission handling
COPY scripts/core/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set proper permissions
RUN chown -R mcpuser:mcpuser /app

# Switch to non-root user
USER mcpuser

# Expose the orchestrator port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Environment variables
ENV NODE_ENV=production
ENV ORCHESTRATOR_PORT=3000
ENV ORCHESTRATOR_HOST=0.0.0.0
ENV LOG_LEVEL=INFO
ENV DISCOVERY_INTERVAL=30000
ENV MCP_TIMEOUT=30000
# Docker configuration for rootless Docker only
ENV DOCKER_MODE=rootless
ENV DOCKER_ROOTLESS_SOCKET_PATH=/run/user/1001/docker.sock
ENV DISCOVERY_RETRY_ATTEMPTS=5
ENV DISCOVERY_RETRY_DELAY=2000

# Labels for container identification
LABEL mcp.orchestrator=true
LABEL mcp.orchestrator.name=core-orchestrator
LABEL mcp.orchestrator.version=1.0.0
LABEL maintainer="NEOMINT Research"
LABEL description="MCP Multi-Agent Orchestrator Core"

# Use entrypoint script for dynamic setup
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "src/core/backend/index.js"]
