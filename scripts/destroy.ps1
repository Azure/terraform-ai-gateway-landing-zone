#!/usr/bin/env pwsh
# =============================================================================
# AI Citadel Governance Hub — Destroy Script
# Usage: ./scripts/destroy.ps1 [dev|prod] [--auto-approve]
# WARNING: This permanently deletes all Citadel resources for the environment.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Environment = 'dev',

    [Parameter(Position = 1)]
    [string]$AutoApprove = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info    { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red; exit 1 }

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$TfvarsFile = Join-Path $RootDir "environments/$Environment.tfvars"

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗'
Write-Host '║       🏰  AI Citadel Governance Hub — Terraform Destroy      ║'
Write-Host '╚══════════════════════════════════════════════════════════════╝'
Write-Host ''
Write-Host '⚠  WARNING: This will PERMANENTLY DELETE all Citadel resources!' -ForegroundColor Red
Write-Host "⚠  Environment: $Environment" -ForegroundColor Red
Write-Host ''

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Err 'terraform not found.' }
if (-not (Test-Path $TfvarsFile)) { Write-Err "Vars file not found: $TfvarsFile" }

Set-Location $RootDir
terraform init -upgrade *> $null

if ($AutoApprove -ne '--auto-approve') {
    $confirm = Read-Host "Type the environment name '$Environment' to confirm destruction"
    if ($confirm -ne $Environment) {
        Write-Info 'Destruction cancelled.'
        exit 0
    }
}

Write-Info 'Running terraform destroy...'
terraform destroy `
    -var-file="$TfvarsFile" `
    -auto-approve `
    2>&1 | ForEach-Object { Write-Host "  $_" }

if ($LASTEXITCODE -ne 0) { Write-Err 'terraform destroy failed.' }

Write-Success "All resources for environment '$Environment' have been destroyed."
