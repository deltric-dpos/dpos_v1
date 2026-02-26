# Post-deploy staging verification (PowerShell)
param(
  [Parameter(Mandatory=$true)][string]$StagingApiUrl
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Checking $StagingApiUrl/healthz"
for ($i=0; $i -lt 60; $i++) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing "$StagingApiUrl/healthz" -TimeoutSec 5
    if ($r.StatusCode -eq 200) { break }
  } catch {}
  Start-Sleep -Seconds 2
}

$r2 = Invoke-WebRequest -UseBasicParsing "$StagingApiUrl/metrics" -TimeoutSec 10
Write-Host "Metrics head:"
$r2.Content.Split("`n") | Select-Object -First 15 | ForEach-Object { $_ }
Write-Host "✅ Staging verification complete."
