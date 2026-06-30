#!/usr/bin/env pwsh
# =============================================================================
# AI Citadel Governance Hub — Bootstrap Terraform Remote State
# Run ONCE before first deploy to create the Azure Storage backend for state.
# Usage: ./scripts/bootstrap-state.ps1 [location]
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info    { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }

$RgName        = 'rg-terraform-state-citadel'
$SaName        = "stcitadelstate$(Get-Random -Minimum 10000 -Maximum 99999)"
$ContainerName = 'citadel-tfstate'

Write-Info 'Creating Terraform remote state backend...'
Write-Info "  Resource Group   : $RgName"
Write-Info "  Storage Account  : $SaName"
Write-Info "  Container        : $ContainerName"
Write-Info "  Location         : $Location"
Write-Host ''

# Create resource group
az group create `
    --name $RgName `
    --location $Location `
    --tags 'Purpose=TerraformState' 'ManagedBy=Bootstrap' `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group: $RgName" }

Write-Success "Resource group created: $RgName"

# Create storage account
az storage account create `
    --name $SaName `
    --resource-group $RgName `
    --location $Location `
    --sku 'Standard_LRS' `
    --kind 'StorageV2' `
    --min-tls-version 'TLS1_2' `
    --allow-blob-public-access false `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create storage account: $SaName" }

Write-Success "Storage account created: $SaName"

# Create container
az storage container create `
    --name $ContainerName `
    --account-name $SaName `
    --auth-mode login `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create container: $ContainerName" }

Write-Success "Container created: $ContainerName"

# Enable versioning (for state file history)
az storage account blob-service-properties update `
    --account-name $SaName `
    --resource-group $RgName `
    --enable-versioning true `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Failed to enable blob versioning.' }

Write-Success 'Blob versioning enabled.'

Write-Host ''
Write-Host '════════════════════════════════════════════════════════'
Write-Host '  ✅  Remote state backend is ready!'
Write-Host ''
Write-Host '  Uncomment and update the backend block in versions.tf:'
Write-Host ''
Write-Host '  backend "azurerm" {'
Write-Host "    resource_group_name  = `"$RgName`""
Write-Host "    storage_account_name = `"$SaName`""
Write-Host "    container_name       = `"$ContainerName`""
Write-Host '    key                  = "citadel.terraform.tfstate"'
Write-Host '  }'
Write-Host '════════════════════════════════════════════════════════'
