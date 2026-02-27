# syntax=docker/dockerfile:1
# D-POS Worker Dockerfile (tolerant + CI-friendly)
#
# Why this exists:
# - Your GH Actions build was failing because the worker build context contained a package-lock.json
#   but *no* package.json, causing `npm ci` to fail (ENOENT /app/package.json).
# - This Dockerfile makes the build succeed while still installing deps when package.json exists.

FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

# Copy the worker source first (some repos may be missing package.json in this folder)
COPY . .

# Install deps only if a package.json is present.
# If npm ci fails (lock mismatch), fallback to npm install.
RUN if [ -f package.json ]; then \
      echo "[worker] package.json found -> installing dependencies"; \
      npm ci --omit=dev || (echo "[worker] npm ci failed -> falling back to npm install" && npm install --omit=dev); \
    else \
      echo "[worker] WARNING: package.json not found in worker build context. Skipping npm install."; \
      echo "[worker] If your worker needs dependencies, add worker/package.json (recommended) or adjust build context."; \
    fi

# Start the worker (adjust entrypoint if your worker main file differs)
CMD ["node", "workerRunner.js"]
