# D-POS Phase 2.1 - Tear down docker stack (PowerShell)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

docker compose down
