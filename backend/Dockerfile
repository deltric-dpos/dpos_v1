
# ================================
# Stage 1: Builder
# ================================
FROM node:22-bookworm-slim AS builder

# Install build tools for native Node modules
RUN apt-get update && apt-get install -y --no-install-recommends     python3     make     g++     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only package files first (better Docker caching)
COPY package*.json ./

# Install dependencies with full logging
RUN npm ci || (echo "----- npm debug log -----" &&     ls -la /root/.npm/_logs || true &&     cat /root/.npm/_logs/*-debug-0.log || true && exit 1)

# Copy the rest of the backend source
COPY . .

# Remove dev dependencies for production image
RUN npm prune --omit=dev

# ================================
# Stage 2: Runtime
# ================================
FROM node:22-bookworm-slim AS runner

WORKDIR /app

ENV NODE_ENV=production

# Copy node_modules and app from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app ./

EXPOSE 4001

CMD ["node", "server.js"]
