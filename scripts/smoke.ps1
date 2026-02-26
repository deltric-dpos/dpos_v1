# D-POS Phase 2.1 - Smoke test (PowerShell)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Ensure node 18+ for built-in fetch; otherwise install node-fetch and run with node
$env:DPOS_BASE_URL = $env:DPOS_BASE_URL ?? "http://localhost:4001"

node ./scripts/smoke.js
