# D-POS Frontend Dockerfile (generic Node runtime)
# Build context MUST be the frontend folder (./frontend)

FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json ./package.json
COPY package-lock.json ./package-lock.json

RUN echo "== Frontend /app listing after manifest copy =="  && ls -la /app  && test -f /app/package.json

RUN npm ci --no-audit --no-fund

COPY . .

# Build if your project supports it (most do). If your frontend is purely static,
# keep build; if it's Next.js, build will create .next; if it's Vite/React, build creates dist.
RUN npm run build

# Start:
# - Next.js usually: npm run start (port 3000)
# - Vite preview: npm run preview (port 4173)
# If your repo uses a different start command, update CMD.
EXPOSE 3000
CMD ["npm", "run", "start"]
