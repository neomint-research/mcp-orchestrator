# MCP Intent Agent Container
FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache curl bash
RUN addgroup -g 1001 -S mcpuser && adduser -S mcpuser -u 1001 -G mcpuser

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY src/modules/intent-agent/ ./src/modules/intent-agent/

RUN chown -R mcpuser:mcpuser /app

USER mcpuser

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3003/health || exit 1

ENV NODE_ENV=production
ENV INTENT_AGENT_PORT=3003
ENV INTENT_AGENT_HOST=0.0.0.0

LABEL mcp.server=true
LABEL mcp.server.name=intent-agent
LABEL mcp.server.port=3003
LABEL mcp.server.protocol=http

CMD ["node", "src/modules/intent-agent/backend/index.js"]
