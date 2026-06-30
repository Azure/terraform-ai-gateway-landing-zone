#!/usr/bin/env pwsh
# =============================================================================
# AI Citadel Governance Hub — Deploy Script
#
# Usage:
#   ./scripts/deploy.ps1 [ENV] [OPTIONS]
#
# Positional:
#   ENV                    dev (default) | prod
#
# Core options:
#   -AutoApprove           Skip interactive confirmation
#
# Optional add-on flags (set feature-flag Terraform variables to true):
#   -WithEntra             Enable Entra ID app registration add-on (§19.13)
#   -WithFoundryConn       Enable Foundry → APIM connection (§2.3)
#   -WithAccessContracts   Enable citadel-access-contracts products (§2.3)
#   -WithMcpSamples        Enable Weather + MS Learn MCP sample APIs
#   -WithJwt               Populate APIM JWT-* named values (implied by -WithEntra)
#   -WithApicOnboarding    Onboard every APIM API into API Center
#   -AllAddons             Shortcut: all -With* flags above
#
# Logic App code publish (on by default):
#   -SkipLogicAppCode      Do not zip+push src/usage-ingestion-logicapp this run
#   -LogicAppCodeOnly      Skip full apply; re-publish workflow code only
#
# Rollout mode:
#   -Phased                Two-phase apply. Phase 1 = core (all add-ons forced
#                          to false). Phase 2 = re-apply with the selected
#                          -With* flags enabled. Mirrors the Bicep
#                          "follow-on deployment" workflow.
#
# Examples:
#   ./scripts/deploy.ps1 dev                                     # core only
#   ./scripts/deploy.ps1 dev -WithEntra -WithFoundryConn         # single apply
#   ./scripts/deploy.ps1 prod -AllAddons -Phased                 # Bicep-style
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Environment = 'dev',

    [switch]$AutoApprove,
    [switch]$Phased,
    [switch]$WithEntra,
    [switch]$WithFoundryConn,
    [switch]$WithAccessContracts,
    [switch]$WithMcpSamples,
    [switch]$WithJwt,
    [switch]$WithApicOnboarding,
    [switch]$AllAddons,
    [switch]$SkipLogicAppCode,
    [switch]$LogicAppCodeOnly,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Colour helpers ---
function Write-Info    { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red; exit 1 }

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 46 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# --- Expand -AllAddons shortcut ---
if ($AllAddons) {
    $WithEntra           = $true
    $WithFoundryConn     = $true
    $WithAccessContracts = $true
    $WithMcpSamples      = $true
    $WithJwt             = $true
    $WithApicOnboarding  = $true
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$TfvarsFile = Join-Path $RootDir "environments/$Environment.tfvars"

# --- Returns -var args for the current rollout phase ---
# $Phase = 0 (single shot), 1 (core phase), 2 (add-ons phase)
function Get-AddonTfArgs {
    param([int]$Phase)
    $overrides = @()
    if ($Phase -eq 1) {
        # Force all add-ons off for core phase
        $overrides += '-var=enable_entra_id_setup=false'
        $overrides += '-var=enable_foundry_apim_connection=false'
        $overrides += '-var=enable_access_contracts=false'
        $overrides += '-var=is_mcp_sample_deployed=false'
        $overrides += '-var=enable_jwt_auth=false'
        $overrides += '-var=enable_api_center_onboarding=false'
    }
    else {
        # Phase 2 or single-shot: set only the ones the user asked for
        if ($WithEntra)           { $overrides += '-var=enable_entra_id_setup=true' }
        if ($WithFoundryConn)     { $overrides += '-var=enable_foundry_apim_connection=true' }
        if ($WithAccessContracts) { $overrides += '-var=enable_access_contracts=true' }
        if ($WithMcpSamples)      { $overrides += '-var=is_mcp_sample_deployed=true' }
        if ($WithJwt)             { $overrides += '-var=enable_jwt_auth=true' }
        if ($WithApicOnboarding)  { $overrides += '-var=enable_api_center_onboarding=true' }
    }

    # Skip workflow-code publish if requested (applies to all phases).
    if ($SkipLogicAppCode) {
        $overrides += '-var=enable_logic_app_code_deploy=false'
    }
    return $overrides
}

# --- Banner ---
Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗'
Write-Host '║       🏰  AI Citadel Governance Hub — Terraform Deploy       ║'
Write-Host '╚══════════════════════════════════════════════════════════════╝'
Write-Host ''
Write-Info "Environment : $Environment"
Write-Info "Vars file   : $TfvarsFile"
Write-Info "Working dir : $RootDir"
if ($AutoApprove) { Write-Info 'Auto-approve: Enabled' }
if ($Phased) { Write-Info 'Rollout     : phased (core → add-ons)' } else { Write-Info 'Rollout     : single apply' }
$AddonsSummary = ''
if ($WithEntra)           { $AddonsSummary += 'entra ' }
if ($WithFoundryConn)     { $AddonsSummary += 'foundry-conn ' }
if ($WithAccessContracts) { $AddonsSummary += 'access-contracts ' }
if ($WithMcpSamples)      { $AddonsSummary += 'mcp-samples ' }
if ($WithJwt)             { $AddonsSummary += 'jwt ' }
if ($WithApicOnboarding)  { $AddonsSummary += 'apic-onboarding ' }
if ($AddonsSummary) { Write-Info "Add-ons     : $AddonsSummary" } else { Write-Info 'Add-ons     : none (core only)' }
Write-Host ''

# --- Pre-flight checks ---
Write-Info 'Running pre-flight checks...'

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Err 'terraform not found. Install from https://developer.hashicorp.com/terraform/install' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Err 'Azure CLI not found. Install from https://aka.ms/installazurecli' }

$TfVersion = ''
try {
    $TfVersion = (terraform version -json 2>$null | ConvertFrom-Json).terraform_version
} catch { $TfVersion = '' }
if (-not $TfVersion) {
    $TfVersion = ((terraform version | Select-Object -First 1) -split '\s+')[1] -replace '^v', ''
}
Write-Info "Terraform version: $TfVersion"

if (-not (Test-Path $TfvarsFile)) { Write-Err "Vars file not found: $TfvarsFile" }

# --- Azure login check ---
Write-Info 'Verifying Azure CLI authentication...'
$AccountJson = az account show --query "{name:name, id:id, user:user.name}" -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $AccountJson) { Write-Err 'Not logged in to Azure. Run: az login' }
$Account          = $AccountJson | ConvertFrom-Json
$SubscriptionName = $Account.name
$SubscriptionId   = $Account.id
$LoggedUser       = $Account.user

Write-Success "Logged in as: $LoggedUser"
Write-Info "Subscription: $SubscriptionName ($SubscriptionId)"

# --- Subscription ID check in tfvars ---
if (Select-String -Path $TfvarsFile -Pattern 'YOUR-SUBSCRIPTION-ID' -Quiet) {
    Write-Warn "subscription_id is still set to YOUR-SUBSCRIPTION-ID in $TfvarsFile"
    Write-Warn "Auto-setting it to the current subscription: $SubscriptionId"
    Copy-Item $TfvarsFile "$TfvarsFile.bak" -Force
    (Get-Content $TfvarsFile -Raw) -replace 'YOUR-SUBSCRIPTION-ID', $SubscriptionId | Set-Content $TfvarsFile -NoNewline
    Write-Success "Updated subscription_id in $TfvarsFile"
}

# --- Register required resource providers ---
Write-Info 'Registering required Azure resource providers (this may take a minute)...'
$Providers = @(
    'Microsoft.AlertsManagement', 'Microsoft.ApiCenter', 'Microsoft.ApiManagement',
    'Microsoft.CognitiveServices', 'Microsoft.DocumentDB', 'Microsoft.EventHub',
    'Microsoft.Insights', 'Microsoft.KeyVault', 'Microsoft.Logic',
    'Microsoft.MachineLearningServices', 'Microsoft.ManagedIdentity', 'Microsoft.Network',
    'Microsoft.OperationalInsights', 'Microsoft.Storage', 'Microsoft.Web'
)

foreach ($provider in $Providers) {
    $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if (-not $state) { $state = 'Unknown' }
    if ($state -eq 'Registered') {
        Write-Host "✅  ${provider}: " -NoNewline
        Write-Host $state -ForegroundColor Green
        continue
    }
    Write-Info "Registering $provider..."
    $regOutput = az provider register --namespace $provider --wait 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to register ${provider}: $regOutput" -ForegroundColor Red
        $cont = Read-Host 'Continue anyway? (y/N)'
        if ($cont -notmatch '^[Yy]$') { Write-Err 'Aborted by user.' }
        continue
    }
    Write-Success "Registered $provider"
}
Write-Success 'All resource providers registered.'

# --- Terraform init ---
Write-Host ''
Write-Info 'Initialising Terraform...'
Set-Location $RootDir
terraform init -upgrade -reconfigure
if ($LASTEXITCODE -ne 0) { Write-Err 'Terraform init failed.' }
Write-Success 'Terraform initialised.'

# --- Terraform validate ---
Write-Info 'Validating Terraform configuration...'
terraform validate
if ($LASTEXITCODE -eq 0) { Write-Success 'Configuration is valid.' } else { Write-Err 'Terraform validation failed.' }

# =============================================================================
# Invoke-PlanAndApply <phase_label> <phase_number>
#   phase_number: 0 = single shot; 1 = core; 2 = add-ons
# =============================================================================
function Invoke-PlanAndApply {
    param(
        [string]$PhaseLabel,
        [int]$Phase
    )

    Write-Host ''
    Write-Host '───────────────────────────────────────────────────────────────'
    Write-Info "Phase: $PhaseLabel"
    Write-Info "This will create/modify Azure resources for the '$PhaseLabel' phase of the deployment."
    Write-Info 'This operation usually takes up-to 10 minutes, depending on the number of resources being provisioned.'
    Write-Info 'The first phase (core) will deploy the baseline infrastructure. The second phase (add-ons) will apply the selected add-on features on top of the baseline.'
    Write-Info 'The first phase (core) may take up-to 30-45 minutes to complete.'
    Write-Host '───────────────────────────────────────────────────────────────'

    # Collect -var args
    $extraVars = @(Get-AddonTfArgs -Phase $Phase)

    if ($extraVars.Count -gt 0) { Write-Info "Overrides: $($extraVars -join ' ')" }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $planFile  = Join-Path $RootDir ".terraform/tfplan-$Environment-$PhaseLabel-$timestamp"
    $planDir   = Split-Path -Parent $planFile
    if (-not (Test-Path $planDir)) { New-Item -ItemType Directory -Path $planDir -Force | Out-Null }

    $planArgs = @("-var-file=$TfvarsFile") + $extraVars + @("-out=$planFile", '-detailed-exitcode')
    terraform plan @planArgs
    $planExit = $LASTEXITCODE

    if ($planExit -eq 0) {
        Write-Success "No changes detected for phase '$PhaseLabel'."
        return
    }
    elseif ($planExit -eq 1) {
        Write-Err "Terraform plan failed (phase: $PhaseLabel)."
    }
    Write-Success "Plan complete for phase '$PhaseLabel' — changes detected."

    if (-not $AutoApprove) {
        Write-Host ''
        Write-Host "Review plan for phase '$PhaseLabel' above." -ForegroundColor Yellow
        $confirm = Read-Host "Type 'yes' to apply"
        if ($confirm -ne 'yes') { Write-Info "Phase '$PhaseLabel' cancelled."; exit 0 }
    }

    Write-Info "Applying plan (phase: $PhaseLabel)..."
    $startTime = Get-Date

    $applyLog = New-TemporaryFile

    terraform apply -auto-approve $planFile 2>&1 | Tee-Object -FilePath $applyLog.FullName
    $applyExit = $LASTEXITCODE

    # Auto-import on "already exists" errors
    if ($applyExit -ne 0 -and (Select-String -Path $applyLog.FullName -Pattern 'already exists' -Quiet)) {
        Write-Warn "Apply failed with 'already exists' errors. Attempting auto-import..."
        $runImport = $true
        if (-not $AutoApprove) {
            $ans = Read-Host 'Auto-import existing resources and retry apply? (Y/n)'
            if ($ans -match '^[Nn]$') { $runImport = $false }
        }
        $importScript = Join-Path $ScriptDir 'import-existing.ps1'
        if ($runImport -and (Test-Path $importScript)) {
            & $importScript $Environment
            if ($LASTEXITCODE -eq 0) { $applyExit = 0 }
        }
    }

    Remove-Item $applyLog.FullName -Force -ErrorAction SilentlyContinue

    $duration = (Get-Date) - $startTime
    $minutes  = [int]$duration.TotalMinutes
    $seconds  = $duration.Seconds

    if ($applyExit -eq 0) {
        Write-Success "Phase '$PhaseLabel' applied successfully (${minutes}m ${seconds}s)."
    }
    else {
        Write-Err "Phase '$PhaseLabel' failed (exit $applyExit)."
    }
}

# --- Execute phases ---
if ($LogicAppCodeOnly) {
    Write-Info 'Logic App code-only mode: re-publishing workflow code without full apply.'
    $applyArgs = @("-var-file=$TfvarsFile", '-target=module.logic_app.null_resource.publish_workflows[0]')
    if ($AutoApprove) { $applyArgs += '-auto-approve' }
    terraform apply @applyArgs
    Write-Success 'Workflow code re-published.'
    exit 0
}

if ($Phased) {
    Invoke-PlanAndApply -PhaseLabel 'core'    -Phase 1
    # If the user didn't request any add-ons, phase 2 is a no-op that will be
    # skipped by "No changes detected".
    Invoke-PlanAndApply -PhaseLabel 'add-ons' -Phase 2
}
else {
    Invoke-PlanAndApply -PhaseLabel 'single' -Phase 0
}

# --- Summary ---
Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗'
Write-Host '║                 ✅  Deployment Successful!                   ║'
Write-Host '╚══════════════════════════════════════════════════════════════╝'
Write-Info 'Deployment outputs:'
terraform output 2>$null
Write-Host ''
Write-Info 'Next steps:'
Write-Host "  1. Validate deployment: ./scripts/validate.ps1 $Environment"
Write-Host '  2. Run validation notebooks in /validation/'
if ($WithEntra) { Write-Host '  3. Entra app secret available in Key Vault as ENTRA-APP-CLIENT-SECRET' }
