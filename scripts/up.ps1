# D-POS Phase 2.1 - Bring up docker stack (PowerShell)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path ".env.backend")) { Copy-Item ".env.backend.example" ".env.backend" -Force }
if (!(Test-Path ".env.worker"))  { Copy-Item ".env.worker.example"  ".env.worker"  -Force }
if (!(Test-Path ".env.frontend")){ Copy-Item ".env.frontend.example" ".env.frontend" -Force }

docker compose up -d --build
docker compose ps
