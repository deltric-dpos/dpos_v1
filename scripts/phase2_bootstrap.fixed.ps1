
param(
    [string]$Owner,
    [string]$Repo,
    [string]$AzureLocation = "southafricanorth"
)

Write-Host "Starting Phase 2 Bootstrap..." -ForegroundColor Cyan

# ---------- Random Secret Generator ----------
function New-RandomSecret {
    -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
}

# ---------- Generate Required Secrets ----------
$internalApiKey = New-RandomSecret
$pgAdmin = "dposadmin"
$pgPass = New-RandomSecret
$pgHost = "dpos-db.postgres.database.azure.com"
$dbName = "dpos"

# FIXED: Proper PowerShell string interpolation
$databaseUrl = "postgres://${pgAdmin}:${pgPass}@${pgHost}:5432/${dbName}?sslmode=require"

Write-Host "Generated Secrets:" -ForegroundColor Yellow
Write-Host "INTERNAL_API_KEY: $internalApiKey"
Write-Host "DATABASE_URL: $databaseUrl"

# ---------- Azure Login ----------
Write-Host "Logging into Azure..."
az login

# ---------- GitHub Login ----------
Write-Host "Authenticating GitHub CLI..."
gh auth status

# ---------- Set GitHub Secrets ----------
Write-Host "Setting GitHub Secrets..." -ForegroundColor Cyan

gh secret set INTERNAL_API_KEY_STAGING --repo "$Owner/$Repo" --body "$internalApiKey"
gh secret set DATABASE_URL_STAGING --repo "$Owner/$Repo" --body "$databaseUrl"

Write-Host "Secrets successfully configured." -ForegroundColor Green

Write-Host "Phase 2 Bootstrap Completed Successfully." -ForegroundColor Green
