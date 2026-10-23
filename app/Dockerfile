# Stage 1: Build Dependencies
FROM node:22-alpine AS builder
WORKDIR /usr/src/app

# Copy package files from the app directory
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Hardened Runtime
FROM node:22-alpine AS runner
WORKDIR /usr/src/app

ENV NODE_ENV=production

# Copy built dependencies and source files with explicit ownership
COPY --chown=node:node --from=builder /usr/src/app/node_modules ./node_modules
COPY --chown=node:node . .

# Run as a secure, non-root user (built into the Node alpine image)
USER node

EXPOSE 3000

# Container health check for ECS/ALB
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
