#!/usr/bin/env pwsh
# =============================================================================
# Auto-import existing Azure resources into Terraform state.
#
# Runs `terraform apply` and, when it fails with "already exists" errors,
# parses each error to extract the Terraform address + Azure resource ID,
# imports them, and retries apply. Repeats until apply succeeds or no new
# imports are detected.
#
# Usage:
#   ./scripts/import-existing.ps1 <env> [-MaxRetries N]
#   ./scripts/import-existing.ps1 dev
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Environment = 'dev',

    [int]$MaxRetries = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info    { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red; exit 1 }

# Safely read a property from a PSCustomObject without tripping Set-StrictMode.
function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# Render a single terraform -json event line to a human-readable form.
# Non-JSON lines are echoed verbatim; JSON events that aren't errors or
# lifecycle markers are suppressed (matching the original behaviour).
function Write-TfEvent {
    param([string]$Line)
    $evt = $null
    try { $evt = $Line | ConvertFrom-Json -ErrorAction Stop } catch { Write-Host $Line; return }
    $msg = Get-Prop $evt '@message'
    if ((Get-Prop $evt '@level') -eq 'error') {
        Write-Host "ERROR: $msg"
    }
    elseif ((Get-Prop $evt 'type') -in @('apply_start', 'apply_complete', 'apply_errored', 'change_summary')) {
        Write-Host $msg
    }
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$TfvarsFile = Join-Path $RootDir "environments/$Environment.tfvars"
if (-not (Test-Path $TfvarsFile)) { Write-Err "Vars file not found: $TfvarsFile" }

Set-Location $RootDir

# Use a workspace-local temp dir for the apply log and per-attempt plan files.
$TmpDir = Join-Path $RootDir '.tf-import-tmp'
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null }
$LogFile = Join-Path $TmpDir "tf-apply.$([System.IO.Path]::GetRandomFileName())"

# Regexes to pull the Azure resource ID / role-assignment GUID out of the
# diagnostic text.
$IdRe   = '"(/subscriptions/[^"]+)"\s+already exists'
$GuidRe = 'existing role assignment is\s+([A-Za-z0-9\-]+)'

try {
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-Info "Apply attempt $attempt/$MaxRetries..."

        # Run apply with -json so we get structured diagnostic events. Tee the
        # raw JSON stream to the log file for parsing while rendering a
        # human-readable view to the terminal.
        terraform apply -var-file="$TfvarsFile" -auto-approve -json 2>&1 |
            Tee-Object -FilePath $LogFile |
            ForEach-Object { Write-TfEvent ([string]$_) }
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Success "Apply succeeded on attempt $attempt."
            exit 0
        }

        # Parse the JSON event stream into IMPORT / ROLE entries. Each
        # diagnostic error carries structured fields (diagnostic.address,
        # diagnostic.summary, diagnostic.detail), so we only need a small
        # regex against the text to recover the Azure ID or role GUID.
        $seen        = @{}
        $imports     = @()  # each entry: [pscustomobject]@{ Addr; Rid }
        $roleImports = @()  # each entry: [pscustomobject]@{ Addr; Guid }

        foreach ($line in (Get-Content -LiteralPath $LogFile)) {
            $line = $line.Trim()
            if (-not $line -or -not $line.StartsWith('{')) { continue }
            $evt = $null
            try { $evt = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ((Get-Prop $evt '@level') -ne 'error') { continue }
            $diag = Get-Prop $evt 'diagnostic'
            $addr = Get-Prop $diag 'address'
            if (-not $addr) { continue }
            $summary = Get-Prop $diag 'summary'
            $detail  = Get-Prop $diag 'detail'
            $blob    = "$summary`n$detail"

            if ($blob -match $IdRe) {
                $rid = $Matches[1]
                $key = "IMPORT`t$addr`t$rid"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $imports += [pscustomobject]@{ Addr = $addr; Rid = $rid }
                }
                continue
            }

            if ($blob -match $GuidRe) {
                $guid = $Matches[1]
                $key  = "ROLE`t$addr`t$guid"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $roleImports += [pscustomobject]@{ Addr = $addr; Guid = $guid }
                }
            }
        }

        if ($imports.Count -eq 0 -and $roleImports.Count -eq 0) {
            Write-Err "Apply failed and no 'already exists' errors were detected. See output above."
        }

        $totalFound = $imports.Count + $roleImports.Count
        Write-Info "Detected $totalFound resource(s) to import:"
        foreach ($item in $imports)     { Write-Host "  - $($item.Addr)" }
        foreach ($item in $roleImports) { Write-Host "  - $($item.Addr) (role assignment)" }

        $importedAny = $false

        # --- Generic "already exists" imports (azurerm + azapi) ---
        foreach ($item in $imports) {
            $addr = $item.Addr
            $rid  = $item.Rid

            # Skip if already in state.
            terraform state show $addr *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Warn "Already in state, skipping: $addr"
                continue
            }

            Write-Info "Importing $addr"
            Write-Info "         <- $rid"
            terraform import -var-file="$TfvarsFile" $addr $rid
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Imported $addr"
                $importedAny = $true
            }
            else {
                Write-Warn "Failed to import $addr — continuing."
            }
        }

        # --- RoleAssignmentExists imports ---
        # azurerm_role_assignment import ID format:
        #   <scope>/providers/Microsoft.Authorization/roleAssignments/<guid>
        # We recover <scope> from the planned resource values.
        foreach ($item in $roleImports) {
            $addr = $item.Addr
            $guid = $item.Guid

            terraform state show $addr *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Warn "Already in state, skipping: $addr"
                continue
            }

            Write-Info "Resolving scope for role assignment: $addr"
            $raPlan = Join-Path $TmpDir "tf-ra-plan.$([System.IO.Path]::GetRandomFileName())"
            terraform plan -var-file="$TfvarsFile" -target="$addr" -out="$raPlan" *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Could not plan $addr to resolve scope — skipping."
                Remove-Item $raPlan -Force -ErrorAction SilentlyContinue
                continue
            }

            $scope = ''
            try {
                $planJson = (terraform show -json $raPlan 2>$null | Out-String) | ConvertFrom-Json
                foreach ($rc in (Get-Prop $planJson 'resource_changes')) {
                    if ((Get-Prop $rc 'address') -eq $addr) {
                        $change = Get-Prop $rc 'change'
                        $after  = Get-Prop $change 'after'
                        $scope  = Get-Prop $after 'scope'
                        break
                    }
                }
            } catch { $scope = '' }
            Remove-Item $raPlan -Force -ErrorAction SilentlyContinue

            if ([string]::IsNullOrEmpty($scope)) {
                Write-Warn "Empty scope for $addr — skipping."
                continue
            }

            $rid = "$scope/providers/Microsoft.Authorization/roleAssignments/$guid"
            Write-Info "Importing $addr"
            Write-Info "         <- $rid"
            terraform import -var-file="$TfvarsFile" $addr $rid
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Imported $addr"
                $importedAny = $true
            }
            else {
                Write-Warn "Failed to import $addr — continuing."
            }
        }

        if (-not $importedAny) {
            Write-Err "No new resources were imported on this attempt; aborting to avoid an infinite loop."
        }
    }

    Write-Err "Reached max retries ($MaxRetries) without a successful apply."
}
finally {
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
