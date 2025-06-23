# MCP Memory Agent Container
FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache curl bash
RUN addgroup -g 1001 -S mcpuser && adduser -S mcpuser -u 1001 -G mcpuser

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY src/modules/memory-agent/ ./src/modules/memory-agent/

RUN mkdir -p /app/data && chown -R mcpuser:mcpuser /app

USER mcpuser

EXPOSE 3002

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3002/health || exit 1

ENV NODE_ENV=production
ENV MEMORY_AGENT_PORT=3002
ENV MEMORY_AGENT_HOST=0.0.0.0
ENV MEMORY_AGENT_DATA=/app/data

LABEL mcp.server=true
LABEL mcp.server.name=memory-agent
LABEL mcp.server.port=3002
LABEL mcp.server.protocol=http

CMD ["node", "src/modules/memory-agent/backend/index.js"]
