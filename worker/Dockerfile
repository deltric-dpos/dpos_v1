# syntax=docker/dockerfile:1
# D-POS Worker Dockerfile (Node)
# Goal: stop CI breaks from `npm ci` by using a more compatible install strategy.
# - Uses Debian slim (more compatible than Alpine for native deps)
# - Uses `npm install --omit=dev` (works even when lockfiles / npm versions vary)
FROM node:20-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NPM_CONFIG_LOGLEVEL=warn
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true
ENV NPM_CONFIG_ENGINE_STRICT=false

COPY package*.json ./
# NOTE: If you later stabilize lockfiles, you can switch back to `npm ci --omit=dev` for determinism.
RUN npm --version && node --version && npm install --omit=dev

COPY . .
CMD ["npm","run","start"]
