# syntax=docker/dockerfile:1
# D-POS Frontend Dockerfile (Node)
# - Build stage installs full deps and runs build if present
# - Runtime stage installs prod deps only (or keeps runtime minimal if app is static)
FROM node:20-bookworm-slim AS build
WORKDIR /app

ENV NODE_ENV=development
ENV NPM_CONFIG_LOGLEVEL=warn
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true
ENV NPM_CONFIG_ENGINE_STRICT=false

COPY package*.json ./
RUN npm --version && node --version && npm install
COPY . .

# If your frontend has a build script, this will run it.
# If not, it will no-op and continue.
RUN (npm run | grep -q " build" && npm run build) || echo "No build script detected; skipping build."

FROM node:20-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NPM_CONFIG_LOGLEVEL=warn
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true
ENV NPM_CONFIG_ENGINE_STRICT=false

COPY package*.json ./
RUN npm --version && node --version && npm install --omit=dev

# Copy source + common build outputs (if they exist)
COPY . .
# If the build produced assets (Vite/CRA/Next/etc.), they remain in the image.
EXPOSE 3000
CMD ["npm","run","start"]
