param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [string]$AzureLocation = "southafricanorth",
  [string]$ResourceGroup = "dpos-staging-rg",
  [string]$Prefix = "dpos",
  [switch]$RunWorkflows
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

Write-Host "== Phase 2 Bootstrap =="
Write-Host "Repo: $Owner/$Repo"
Write-Host "AzureLocation: $AzureLocation"
Write-Host "ResourceGroup: $ResourceGroup"
Write-Host "Prefix: $Prefix"

# Ensure logins
Write-Host "Checking Azure login..."
try { az account show | Out-Null } catch { throw "Not logged into Azure. Run: az login" }

Write-Host "Checking GitHub CLI auth..."
try { gh auth status | Out-Null } catch { throw "Not logged into GitHub CLI. Run: gh auth login" }

# 1) Copy workflows into repo
$wfDst = Join-Path -Path (Get-Location) -ChildPath ".github/workflows"
New-Item -ItemType Directory -Force -Path $wfDst | Out-Null
Copy-Item -Force -Recurse ".\workflows\*.yml" $wfDst

# 2) Create RG
Write-Host "Creating/ensuring resource group..."
az group create -n $ResourceGroup -l $AzureLocation | Out-Null

# 3) Create ACR
$acrName = ($Prefix + "acr" + (Get-Random -Minimum 1000 -Maximum 9999)).ToLower()
Write-Host "Creating ACR: $acrName"
az acr create -n $acrName -g $ResourceGroup --sku Basic --admin-enabled true | Out-Null

$acrLoginServer = (az acr show -n $acrName -g $ResourceGroup --query loginServer -o tsv)
$acrUser = (az acr credential show -n $acrName -g $ResourceGroup --query username -o tsv)
$acrPass = (az acr credential show -n $acrName -g $ResourceGroup --query "passwords[0].value" -o tsv)

# 4) Create Container Apps Env
$caEnv = ($Prefix + "-staging-env")
Write-Host "Creating/ensuring Container Apps env: $caEnv"
az extension add --name containerapp --upgrade | Out-Null
az containerapp env create -n $caEnv -g $ResourceGroup -l $AzureLocation | Out-Null

# 5) Create Postgres Flexible Server (staging)
$pgServer = ($Prefix + "-pg-" + (Get-Random -Minimum 1000 -Maximum 9999)).ToLower()
$dbName = "dpos"
$pgAdmin = "dposadmin"
# generate strong password
$pgPass = [System.Web.Security.Membership]::GeneratePassword(28,6)

Write-Host "Creating Postgres flexible server: $pgServer"
az postgres flexible-server create `
  -g $ResourceGroup `
  -n $pgServer `
  -l $AzureLocation `
  --admin-user $pgAdmin `
  --admin-password $pgPass `
  --sku-name Standard_B1ms `
  --storage-size 32 `
  --version 16 `
  --public-access 0.0.0.0 `
  --yes | Out-Null

az postgres flexible-server db create -g $ResourceGroup -s $pgServer -d $dbName | Out-Null

$pgHost = (az postgres flexible-server show -g $ResourceGroup -n $pgServer --query fullyQualifiedDomainName -o tsv)
$databaseUrl = "postgres://$pgAdmin:$pgPass@$pgHost:5432/$dbName?sslmode=require"

# 6) Create Container Apps (API/Worker/Web) with placeholder images first
$apiApp = ($Prefix + "-api-staging")
$workerApp = ($Prefix + "-worker-staging")
$webApp = ($Prefix + "-web-staging")

# INTERNAL API KEY for staging
$internalKey = (New-Guid).Guid.Replace("-", "") + (New-Guid).Guid.Replace("-", "")

Write-Host "Creating API Container App: $apiApp"
az containerapp create `
  -n $apiApp -g $ResourceGroup --environment $caEnv `
  --image "$acrLoginServer/dpos-api:latest" `
  --registry-server $acrLoginServer `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --ingress external --target-port 4001 `
  --env-vars `
    PORT=4001 `
    DPOS_ENV=staging `
    INTERNAL_API_KEY=$internalKey `
    DATABASE_URL="$databaseUrl" | Out-Null

# Get public URL
$apiFqdn = (az containerapp show -n $apiApp -g $ResourceGroup --query properties.configuration.ingress.fqdn -o tsv)
$stagingApiPublicUrl = "https://$apiFqdn"

Write-Host "Creating WORKER Container App: $workerApp"
az containerapp create `
  -n $workerApp -g $ResourceGroup --environment $caEnv `
  --image "$acrLoginServer/dpos-worker:latest" `
  --registry-server $acrLoginServer `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --ingress disabled `
  --env-vars `
    DPOS_ENV=staging `
    DPOS_BASE_URL=$stagingApiPublicUrl `
    INTERNAL_API_KEY=$internalKey `
    DPOS_TRAFFIC=system | Out-Null

Write-Host "Creating WEB Container App: $webApp"
az containerapp create `
  -n $webApp -g $ResourceGroup --environment $caEnv `
  --image "$acrLoginServer/dpos-web:latest" `
  --registry-server $acrLoginServer `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --ingress external --target-port 3000 `
  --env-vars `
    NODE_ENV=production `
    PORT=3000 `
    NEXT_PUBLIC_API_BASE=$stagingApiPublicUrl | Out-Null

# 7) Create Service Principal for GitHub Actions (classic client secret)
# NOTE: This is the simplest reliable automation path.
Write-Host "Creating Service Principal for GitHub Actions..."
$subId = (az account show --query id -o tsv)
$spName = "$Prefix-gh-actions-$((Get-Random -Minimum 1000 -Maximum 9999))"
$spJson = az ad sp create-for-rbac `
  --name $spName `
  --role contributor `
  --scopes "/subscriptions/$subId/resourceGroups/$ResourceGroup" `
  --sdk-auth

# 8) Set GitHub secrets
Write-Host "Setting GitHub secrets..."
$repoFull = "$Owner/$Repo"

# Helper to set secret (stdin)
function Set-GHSecret($name, $value) {
  $value | gh secret set $name -R $repoFull
}

Set-GHSecret "AZURE_CREDENTIALS" $spJson
Set-GHSecret "AZURE_SUBSCRIPTION_ID" $subId
Set-GHSecret "AZURE_RESOURCE_GROUP" $ResourceGroup
Set-GHSecret "AZURE_LOCATION" $AzureLocation
Set-GHSecret "AZURE_CONTAINERAPPS_ENV" $caEnv
Set-GHSecret "AZURE_ACR_NAME" $acrName
Set-GHSecret "INTERNAL_API_KEY_STAGING" $internalKey
Set-GHSecret "DATABASE_URL_STAGING" $databaseUrl
Set-GHSecret "AZURE_API_APP_NAME" $apiApp
Set-GHSecret "AZURE_WORKER_APP_NAME" $workerApp
Set-GHSecret "AZURE_WEB_APP_NAME" $webApp
Set-GHSecret "STAGING_API_PUBLIC_URL" $stagingApiPublicUrl
# Worker uses public URL for simplicity; if you later enable internal ingress + private DNS, set INTERNAL URL separately.
Set-GHSecret "STAGING_API_INTERNAL_URL" $stagingApiPublicUrl

Write-Host "✅ Secrets set for $repoFull"

# 9) Commit/push workflow files (Step 2)
Write-Host "Committing workflows..."
git add .github/workflows | Out-Null
git commit -m "Phase 2.2 - CI/CD (ACR + Azure Container Apps staging)" | Out-Null
git push | Out-Null

Write-Host "✅ Workflows pushed. CI should run now."

if ($RunWorkflows) {
  Write-Host "Triggering build-push and deploy workflows via gh..."
  gh workflow run dpos-build-push -R $repoFull
  gh workflow run dpos-deploy-staging -R $repoFull
}

Write-Host ""
Write-Host "STAGING API: $stagingApiPublicUrl"
Write-Host "STAGING WEB: (check containerapp $webApp fqdn)"
Write-Host ""
Write-Host "Next: verify staging:"
Write-Host "  ./scripts/verify_staging.ps1 -StagingApiUrl $stagingApiPublicUrl"
