#!/usr/bin/env pwsh
# =============================================================================
# Citadel Access Contracts — Deploy Script
#
# Onboards a use-case (APIM products, subscriptions, optional Key Vault secrets
# and Foundry connections) to an existing AI Governance Hub APIM instance using
# Terraform.
#
# Usage:
#   ./scripts/deploy.ps1 [OPTIONS]
#
# Options:
#   -AutoApprove      Skip interactive confirmation
#   -PlanOnly         Show plan without applying
#   -Destroy          Tear down the onboarded use-case resources
#   -VarFile FILE     Path to .tfvars file (default: terraform.tfvars)
#   -Help             Show this help message
#
# Examples:
#   ./scripts/deploy.ps1                            # Plan + apply with confirmation
#   ./scripts/deploy.ps1 -AutoApprove              # Apply without confirmation
#   ./scripts/deploy.ps1 -PlanOnly                 # Show plan only
#   ./scripts/deploy.ps1 -VarFile my-env.tfvars    # Use a custom var file
#   ./scripts/deploy.ps1 -Destroy                  # Remove the use-case resources
# =============================================================================

[CmdletBinding()]
param(
    [switch]$AutoApprove,
    [switch]$PlanOnly,
    [switch]$Destroy,
    [string]$VarFile = 'terraform.tfvars',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Colour helpers ---
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

if ($Help) {
    foreach ($line in (Get-Content $PSCommandPath | Select-Object -Skip 1)) {
        if ($line -notmatch '^#') { break }
        $line -replace '^# ?', ''
    }
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir

Set-Location $RootDir

# --- Validate prerequisites ---
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Err 'terraform CLI not found. Install from https://developer.hashicorp.com/terraform/install' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Err 'Azure CLI not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli' }

# --- Check tfvars file ---
if (-not (Test-Path $VarFile)) {
    Write-Err "Variables file '$VarFile' not found.`n  Copy terraform.tfvars.example to terraform.tfvars and update with your values."
}

# --- Check Azure authentication ---
Write-Info 'Verifying Azure CLI authentication...'
az account show *> $null
if ($LASTEXITCODE -ne 0) { Write-Err "Not logged in to Azure CLI. Run 'az login' first." }

$Subscription = az account show --query id -o tsv
$AccountName  = az account show --query name -o tsv
Write-Info "Using subscription: $AccountName ($Subscription)"

# --- Terraform init ---
Write-Info 'Initializing Terraform...'
terraform init
if ($LASTEXITCODE -ne 0) { Write-Err 'Terraform init failed.' }

# Existing products, policies, subscriptions and API links are adopted by the
# import {} blocks in imports.tf (idempotent re-runs).

# --- Terraform action ---
if ($Destroy) {
    Write-Warn 'DESTROYING the onboarded use-case resources...'
    if ($AutoApprove) {
        terraform destroy -var-file="$VarFile" -auto-approve
    }
    else {
        terraform destroy -var-file="$VarFile"
    }
    if ($LASTEXITCODE -ne 0) { Write-Err 'Destroy aborted/failed.' }
    Write-Success 'Destroy complete.'
}
elseif ($PlanOnly) {
    Write-Info 'Running plan...'
    terraform plan -var-file="$VarFile" -out=tfplan
    if ($LASTEXITCODE -ne 0) { Write-Err 'Plan failed.' }
    Write-Success "Plan saved to 'tfplan'. Review above and run './scripts/deploy.ps1' to apply."
}
else {
    Write-Info 'Planning deployment...'
    terraform plan -var-file="$VarFile" -out=tfplan
    if ($LASTEXITCODE -ne 0) { Write-Err 'Plan failed.' }

    Write-Host ''
    if ($AutoApprove) {
        Write-Info 'Applying (auto-approved)...'
        terraform apply -auto-approve tfplan
    }
    else {
        Write-Host 'Review the plan above. Continue?' -ForegroundColor Yellow
        $confirm = Read-Host '  Apply changes? [y/N]'
        if ($confirm -match '^[Yy]$') {
            terraform apply tfplan
        }
        else {
            Write-Info 'Cancelled.'
            exit 0
        }
    }
    if ($LASTEXITCODE -ne 0) { Write-Err 'Apply failed.' }

    Write-Host ''
    Write-Success 'Citadel Access Contracts onboarding complete!'
    Write-Host ''
    Write-Info 'Deployed products:'
    $outJson = terraform output -json products 2>$null | Out-String
    if ($outJson.Trim()) {
        try {
            $data  = $outJson | ConvertFrom-Json
            $props = $data.PSObject.Properties
            if ($props.Count -eq 0) {
                Write-Host '  (run terraform output products to inspect)'
            }
            else {
                foreach ($p in $props) {
                    $productId = Get-Prop $p.Value 'product_id'
                    Write-Host "  $($p.Name): $productId"
                }
            }
        } catch {
            Write-Host '  (run terraform output products to inspect)'
        }
    }
}
