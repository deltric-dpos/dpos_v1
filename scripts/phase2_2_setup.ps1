param(
  [string]$Owner,
  [string]$Repo = "dpos_v1",
  [string]$AzureLocation = "southafricanorth",
  [string]$ResourceGroup = "dpos-staging-rg",
  [string]$Prefix = "dpos",
  [switch]$SkipBranchProtection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name"
  }
}

Require-Cmd git
Require-Cmd az
Require-Cmd gh
Require-Cmd docker

function Resolve-RepoFromRemote {
  $remote = (git remote get-url origin) 2>$null
  if (-not $remote) { return $null }

  # SSH: git@github.com:owner/repo.git
  if ($remote -match "^git@github\.com:(?<owner>[^/]+)/(?<repo>[^.]+)(\.git)?$") {
    return @{ owner = $Matches.owner; repo = $Matches.repo }
  }

  # HTTPS: https://github.com/owner/repo.git
  if ($remote -match "^https://github\.com/(?<owner>[^/]+)/(?<repo>[^.]+)(\.git)?$") {
    return @{ owner = $Matches.owner; repo = $Matches.repo }
  }

  return $null
}

if (-not $Owner) {
  $rr = Resolve-RepoFromRemote
  if (-not $rr) {
    throw "Could not resolve GitHub owner/repo from git remote. Provide -Owner and -Repo."
  }
  $Owner = $rr.owner
  $Repo  = $rr.repo
}

$repoFull = "$Owner/$Repo"
Write-Host "== Phase 2.2 Setup ==" -ForegroundColor Cyan
Write-Host "Repo: $repoFull"
Write-Host "AzureLocation: $AzureLocation"
Write-Host "ResourceGroup: $ResourceGroup"
Write-Host "Prefix: $Prefix"

# Ensure auth
try { gh auth status | Out-Null } catch { throw "Not logged into GitHub CLI. Run: gh auth login" }
try { az account show | Out-Null } catch { throw "Not logged into Azure CLI. Run: az login" }

# Ensure subscription exists / selected
$subId = (az account show --query id -o tsv)
if (-not $subId) { throw "No Azure subscription selected. Ensure your ISV Azure Sponsorship subscription is active and selected." }

# Ensure repo has required files (workflows should already be present if you unzipped the pack into the repo root)
if (-not (Test-Path ".\.github\workflows\dpos-ci-smoke.yml")) {
  throw "Missing .github/workflows/dpos-ci-smoke.yml. Ensure you unzipped the Phase 2.2 pack into the repo root."
}
if (-not (Test-Path ".\.github\workflows\dpos-build-push-acr.yml")) {
  throw "Missing .github/workflows/dpos-build-push-acr.yml. Ensure you unzipped the Phase 2.2 pack into the repo root."
}
if (-not (Test-Path ".\scripts\smoke.js")) {
  throw "Missing scripts/smoke.js. Ensure you unzipped the Phase 2.2 pack into the repo root."
}

# Create RG
Write-Host "Ensuring Azure Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $AzureLocation | Out-Null

# Create ACR
$acrName = ($Prefix + "acr" + (Get-Random -Minimum 1000 -Maximum 9999)).ToLower()
Write-Host "Creating Azure Container Registry: $acrName" -ForegroundColor Yellow
az acr create -n $acrName -g $ResourceGroup --sku Basic --admin-enabled true | Out-Null

# Create Service Principal scoped to RG
Write-Host "Creating Service Principal for GitHub Actions..." -ForegroundColor Yellow
$spName = "$Prefix-gha-$((Get-Random -Minimum 1000 -Maximum 9999))"
$spJson = az ad sp create-for-rbac `
  --name $spName `
  --role contributor `
  --scopes "/subscriptions/$subId/resourceGroups/$ResourceGroup" `
  --sdk-auth

if (-not $spJson) { throw "Failed to create Service Principal. Ensure your Azure account has permission to create service principals." }

# Set GitHub secrets
Write-Host "Setting GitHub secrets..." -ForegroundColor Yellow
function Set-GHSecret($name, $value) { $value | gh secret set $name -R $repoFull }

Set-GHSecret "AZURE_CREDENTIALS" $spJson
Set-GHSecret "AZURE_SUBSCRIPTION_ID" $subId
Set-GHSecret "AZURE_RESOURCE_GROUP" $ResourceGroup
Set-GHSecret "AZURE_LOCATION" $AzureLocation
Set-GHSecret "AZURE_ACR_NAME" $acrName

# Create Environments
Write-Host "Creating GitHub Environments (staging, production)..." -ForegroundColor Yellow
gh api -X PUT "repos/$repoFull/environments/staging" | Out-Null
gh api -X PUT "repos/$repoFull/environments/production" | Out-Null

# Branch protection payload
$defaultBranch = (gh repo view $repoFull --json defaultBranchRef -q ".defaultBranchRef.name")
if (-not $defaultBranch) { $defaultBranch = "main" }

$protection = @{
  required_status_checks = @{
    strict = $true
    contexts = @("dpos-ci-smoke")
  }
  enforce_admins = $false
  required_pull_request_reviews = @{
    dismiss_stale_reviews = $true
    required_approving_review_count = 1
  }
  restrictions = $null
  required_linear_history = $true
  allow_force_pushes = $false
  allow_deletions = $false
  required_conversation_resolution = $true
} | ConvertTo-Json -Depth 10

$tmp = Join-Path $env:TEMP "dpos_branch_protection.json"
$protection | Out-File -FilePath $tmp -Encoding utf8

if (-not $SkipBranchProtection) {
  Write-Host "Applying Branch Protection on $defaultBranch..." -ForegroundColor Yellow
  gh api -X PUT "repos/$repoFull/branches/$defaultBranch/protection" `
    -H "Accept: application/vnd.github+json" `
    --input $tmp | Out-Null
  Write-Host "Branch protection applied on $defaultBranch." -ForegroundColor Green
} else {
  Write-Host "Skipped branch protection (-SkipBranchProtection)." -ForegroundColor Yellow
}

# Commit + push
Write-Host "Committing Phase 2.2 changes..." -ForegroundColor Yellow
git add .github/workflows scripts/smoke.js | Out-Null
try { git commit -m "Phase 2.2: CI/CD hardening (ACR build/push + smoke)" | Out-Null } catch { Write-Host "No changes to commit (already applied)." -ForegroundColor DarkYellow }
git push | Out-Null

Write-Host ""
Write-Host "✅ Phase 2.2 setup complete." -ForegroundColor Green
Write-Host "ACR: $acrName.azurecr.io"
Write-Host "Next: GitHub → Actions → run 'dpos-build-push-acr' or push to main/master."
Write-Host "Production approvals: Repo Settings → Environments → production → Required reviewers (set yourself)."
