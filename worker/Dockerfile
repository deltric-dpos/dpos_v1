# D-POS Worker Dockerfile (fail-fast, CI-proof)
# Build context MUST be the worker folder (./worker)

FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

# Copy manifest(s) explicitly (no globs that can hide problems)
COPY package.json ./package.json
# lockfile is optional but preferred
COPY package-lock.json ./package-lock.json

# Fail fast with a clear message if manifest didn't arrive in the image
RUN echo "== Worker /app listing after manifest copy =="  && ls -la /app  && test -f /app/package.json

# Install deps (CI-friendly)
RUN npm ci --omit=dev --no-audit --no-fund

# Copy the rest of the worker source
COPY . .

# Fail fast if entrypoint missing (adjust if your worker entry differs)
RUN test -f /app/index.js -o -f /app/workerRunner.js -o -f /app/src/index.js || (echo "ERROR: worker entry file not found (expected index.js/workerRunner.js/src/index.js)" && ls -la /app && exit 1)

# Default command: try index.js; if you use workerRunner.js, change CMD accordingly
CMD ["node", "index.js"]
