<#
dpos_phase2_bootstrap_repo.safe.ps1
Purpose (SAFE MODE):
  Fulfill Phase 2 initial requirements WITHOUT renaming/moving your existing working folder.
  This avoids Windows "in use" / "access denied" issues.

What it does:
  1) Clones the real GitHub repo into Documents\<Repo> (if missing)
  2) Copies selected artifacts from an existing working folder into the cloned repo:
       - .github\workflows
       - scripts
       - (optional) other folders/files you choose
  3) Normalizes workflow filenames to .yml (fixes no-extension/.yaml/.yml.txt)
  4) Commits + pushes to origin
  5) (optional) runs scripts\phase2_2_setup.ps1 after push

Run:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\dpos_phase2_bootstrap_repo.safe.ps1 -Owner "deltric-dpos" -Repo "dpos_v1"

Optional:
  -SourceFolderName "Deltric_Intergrated"
  -DocumentsRoot "C:\Users\<you>\Documents"
  -CopyExtras "backend","package.json",".env.example"
  -CommitMessage "Phase 2.2: add workflows + scripts"
  -RunPhase2Setup

Notes:
  - Does NOT touch/rename/delete the source folder.
  - Does NOT copy any .git folder from source (protects the cloned repo).
  - If files are locked, it will warn and continue, showing what could not be copied.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,

  [string]$SourceFolderName = "Deltric_Intergrated",
  [string]$DocumentsRoot = [Environment]::GetFolderPath("MyDocuments"),

  [string[]]$CopyExtras = @(),

  [string]$CommitMessage = "Bootstrap Phase 2 automation into repo",
  [switch]$RunPhase2Setup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]   $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Require-Cmd([string]$name){
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Fail "Missing required command: $name"
  }
}

Require-Cmd git

$hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
$hasAz = [bool](Get-Command az -ErrorAction SilentlyContinue)

$sourcePath = Join-Path $DocumentsRoot $SourceFolderName
$repoPath   = Join-Path $DocumentsRoot $Repo
$repoUrl    = "https://github.com/$Owner/$Repo.git"

Info "DocumentsRoot: $DocumentsRoot"
Info "SourcePath:    $sourcePath"
Info "RepoPath:      $repoPath"
Info "RepoURL:       $repoUrl"

if (-not (Test-Path $sourcePath)) {
  Fail "Source folder not found: $sourcePath (set -SourceFolderName or move your working folder into Documents)."
}

# Ensure repo exists (clone if missing)
if (-not (Test-Path $repoPath)) {
  Info "Cloning repo into: $repoPath"
  git clone $repoUrl $repoPath | Out-Host
  Ok "Cloned repo."
} else {
  Info "Repo folder already exists: $repoPath"
}

# Validate repo is a git repository
Push-Location $repoPath
try {
  git rev-parse --show-toplevel | Out-Null
  Ok "Repo is a valid git repository."
} catch {
  Fail "RepoPath exists but is not a git repository: $repoPath"
} finally {
  Pop-Location
}

# Copy targets (always)
$targets = @(
  ".github\workflows",
  "scripts"
)

# Copy any extras the caller asked for
foreach ($x in $CopyExtras) { $targets += $x }
$targets = $targets | Select-Object -Unique

function Copy-TreeSafe([string]$from, [string]$to){
  try {
    if (-not (Test-Path $from)) { return $false }

    # Never copy .git from source
    if ((Split-Path $from -Leaf).ToLower() -eq ".git") { return $false }

    $toDir = Split-Path $to -Parent
    if ($toDir -and -not (Test-Path $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }

    $item = Get-Item $from -ErrorAction Stop
    if ($item.PSIsContainer) {
      New-Item -ItemType Directory -Path $to -Force | Out-Null
      Copy-Item -Recurse -Force (Join-Path $from "*") $to -ErrorAction Stop
    } else {
      Copy-Item -Force $from $to -ErrorAction Stop
    }
    return $true
  } catch {
    Warn "Copy failed: $from -> $to"
    Warn "Reason: $($_.Exception.Message)"
    return $false
  }
}

Info "Copying selected artifacts into the cloned repo..."
foreach ($t in $targets) {
  $from = Join-Path $sourcePath $t
  $to   = Join-Path $repoPath   $t
  $ok = Copy-TreeSafe -from $from -to $to
  if ($ok) { Ok "Copied: $t" } else { Warn "Skipped/Failed: $t (missing or locked)" }
}

# Normalize workflows
$wfDir = Join-Path $repoPath ".github\workflows"
if (Test-Path $wfDir) {
  Info "Normalizing workflow filenames in: $wfDir"
  $items = Get-ChildItem -Path $wfDir -File -ErrorAction SilentlyContinue
  foreach ($f in $items) {
    if ([string]::IsNullOrWhiteSpace($f.Extension)) {
      $newName = $f.Name + ".yml"
      Warn "Renaming (no extension): $($f.Name) -> $newName"
      Rename-Item -Path $f.FullName -NewName $newName -Force
      continue
    }
    if ($f.Extension -ieq ".yaml") {
      $newName = ([IO.Path]::GetFileNameWithoutExtension($f.Name) + ".yml")
      Warn "Renaming (.yaml -> .yml): $($f.Name) -> $newName"
      Rename-Item -Path $f.FullName -NewName $newName -Force
      continue
    }
    if ($f.Name.ToLower().EndsWith(".yml.txt")) {
      $newName = $f.Name.Substring(0, $f.Name.Length - 4)
      Warn "Renaming (.yml.txt -> .yml): $($f.Name) -> $newName"
      Rename-Item -Path $f.FullName -NewName $newName -Force
      continue
    }
  }
  Ok "Workflow normalization complete."
} else {
  Warn "No workflows directory found in repo. (Expected .github\workflows)"
}

# Commit + push
Push-Location $repoPath
try {
  Info "Remote:"
  git remote -v | Out-Host

  Info "Git status:"
  git status | Out-Host

  git add -A

  $pending = git status --porcelain
  if ([string]::IsNullOrWhiteSpace($pending)) {
    Ok "No changes to commit."
  } else {
    Info "Committing..."
    git commit -m $CommitMessage | Out-Host
    Ok "Committed."
    Info "Pushing..."
    git push | Out-Host
    Ok "Pushed."
  }

  if ($RunPhase2Setup) {
    $setup = Join-Path $repoPath "scripts\phase2_2_setup.ps1"
    if (Test-Path $setup) {
      if (-not $hasGh) { Warn "gh CLI not found. Phase 2.2 provisioning needs GitHub auth (gh auth login)." }
      if (-not $hasAz) { Warn "az CLI not found. Phase 2.2 provisioning needs Azure CLI." }
      Info "Running Phase 2.2 setup: $setup"
      & $setup -Owner $Owner -Repo $Repo
      Ok "Phase 2.2 setup finished (see output above)."
    } else {
      Warn "Phase 2.2 setup script not found at: $setup"
    }
  }

  Write-Host ""
  Ok "SAFE bootstrap complete."
  Write-Host "Next checks (from repo root):" -ForegroundColor Cyan
  Write-Host "  git status"
  Write-Host "  dir .\.github\workflows"
  Write-Host "  gh auth status"
  Write-Host "  az account show"
} finally {
  Pop-Location
}
