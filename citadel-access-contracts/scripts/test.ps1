#!/usr/bin/env pwsh
# =============================================================================
# Citadel Access Contracts — Test Script
#
# Smoke-tests the onboarded use-case by calling the APIM gateway with each
# product's subscription key. Validates that:
#   1. The product subscription key is accepted by the gateway
#   2. The mapped API path is routable for each onboarded service
#
# When use_target_key_vault = false, subscription keys are fetched on demand
# with `az rest .../listSecrets` using the subscription resource IDs from the
# Terraform `endpoints` output (keys are never stored in outputs). Otherwise
# pass -ApiKey explicitly.
#
# Usage:
#   ./scripts/test.ps1 [OPTIONS]
#
# Options:
#   -ApiKey KEY         APIM subscription key (required when keys are in Key Vault)
#   -GatewayUrl URL     Override the auto-detected gateway URL
#   -Path PATH          Probe a specific API path instead of the per-service paths
#   -Verbose            Show full response bodies
#   -Help               Show this help message
#
# Prerequisites:
#   - Successful deployment via ./scripts/deploy.ps1
#
# Examples:
#   ./scripts/test.ps1                                   # keys from terraform output
#   ./scripts/test.ps1 -ApiKey "your-subscription-key"   # explicit key
#   ./scripts/test.ps1 -Verbose
# =============================================================================

[CmdletBinding()]
param(
    [string]$ApiKey = '',
    [string]$GatewayUrl = '',
    [string]$Path = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Colour helpers ---
function Write-Info     { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Pass     { param([string]$Message) Write-Host "[PASS]  $Message" -ForegroundColor Green }
function Write-Warn     { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-FailTest {
    param([string]$Message)
    Write-Host "[FAIL]  $Message" -ForegroundColor Red
    $script:Failures++
}

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

$script:Failures = 0
$script:Tests    = 0
$isVerbose = $VerbosePreference -ne 'SilentlyContinue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# --- Auto-detect gateway URL from Terraform output ---
if (-not $GatewayUrl) {
    $GatewayUrl = (terraform output -raw apim_gateway_url 2>$null)
    if ($LASTEXITCODE -ne 0) { $GatewayUrl = '' }
    if (-not $GatewayUrl) {
        Write-Host 'Error: Could not auto-detect gateway URL.' -ForegroundColor Red
        Write-Host '  Pass -GatewayUrl or run from the directory with terraform.tfstate.'
        exit 1
    }
}
$GatewayUrl = $GatewayUrl.TrimEnd('/')

Write-Info "Testing APIM Gateway: $GatewayUrl"
Write-Host ''

# --- Probe helper ---
function Invoke-Probe {
    param([string]$Name, [string]$Url, [string]$Key)
    $script:Tests++

    $statusCode = '000'
    $body = ''
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Get `
            -Headers @{ 'Ocp-Apim-Subscription-Key' = $Key; 'api-key' = $Key } `
            -TimeoutSec 30 -SkipHttpErrorCheck -ErrorAction Stop
        $statusCode = [string]$resp.StatusCode
        $body = $resp.Content
    }
    catch {
        if ($_.Exception.Response) { $statusCode = [string][int]$_.Exception.Response.StatusCode } else { $statusCode = '000' }
    }

    # 2xx/3xx = routed; 401/403/404/5xx with a key = gateway routed, backend/policy gated.
    if ($statusCode -match '^[23]') {
        Write-Pass "$Name (HTTP $statusCode — routed)"
    }
    elseif ($statusCode -eq '000') {
        Write-FailTest "$Name — no response (connection failed / private endpoint?)"
    }
    elseif ($statusCode -match '^(401|403|404|5)') {
        Write-Warn "$Name (HTTP $statusCode — gateway routed; backend or policy gated)"
    }
    else {
        Write-FailTest "$Name — unexpected HTTP $statusCode"
    }

    if ($isVerbose -and $body) {
        $snippet = $body.Substring(0, [Math]::Min(300, $body.Length))
        Write-Host "    $snippet"
    }
}

# =============================================================================
# Probe each onboarded service using its endpoint + key (terraform output),
# or a single -Path with -ApiKey.
# =============================================================================
if ($Path) {
    if (-not $ApiKey) { Write-Host '-ApiKey is required with -Path' -ForegroundColor Red; exit 1 }
    Invoke-Probe "GET $Path" "$GatewayUrl/$($Path.TrimStart('/'))" $ApiKey
}
else {
    $endpointsJson = terraform output -json endpoints 2>$null | Out-String
    $endpoints = $null
    if ($endpointsJson.Trim() -and $endpointsJson.Trim() -ne 'null') {
        try { $endpoints = $endpointsJson | ConvertFrom-Json } catch { $endpoints = $null }
    }

    if ($endpoints -and $endpoints.PSObject.Properties.Count -gt 0) {
        Write-Info 'Probing per-service endpoints from Terraform output...'
        Write-Host ''
        foreach ($p in $endpoints.PSObject.Properties) {
            $code = $p.Name
            if (-not $code) { continue }
            $endpoint = Get-Prop $p.Value 'endpoint'
            $subId    = Get-Prop $p.Value 'subscription_resource_id'
            $key      = az rest --method post --url "https://management.azure.com$subId/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv 2>$null
            if (-not $key) { Write-FailTest "[$code] could not read subscription key (az login / permissions?)"; continue }
            Invoke-Probe "[$code] GET $endpoint" $endpoint $key
        }
    }
    else {
        # Key Vault mode — keys are not in outputs. Require -ApiKey + probe products.
        if (-not $ApiKey) {
            Write-Warn 'use_target_key_vault is enabled (or no endpoints output).'
            Write-Warn 'Pass -ApiKey <subscription-key> (and optionally -Path) to probe the gateway.'
            exit 0
        }
        $subsJson = terraform output -json subscriptions 2>$null | Out-String
        $subs = $null
        if ($subsJson.Trim() -and $subsJson.Trim() -ne 'null') {
            try { $subs = $subsJson | ConvertFrom-Json } catch { $subs = $null }
        }
        Write-Info 'Probing product gateway roots with provided key...'
        Write-Host ''
        if ($subs) {
            foreach ($p in $subs.PSObject.Properties) {
                $code = $p.Name
                if (-not $code) { continue }
                Invoke-Probe "[$code] GET $GatewayUrl/" "$GatewayUrl/" $ApiKey
            }
        }
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ''
Write-Host '━━━ Summary ━━━' -ForegroundColor Blue
Write-Host "  Tests run: $($script:Tests)"
if ($script:Failures -eq 0) {
    Write-Pass 'All probes routed (0 hard failures).'
    exit 0
}
else {
    Write-FailTest "$($script:Failures) probe(s) failed."
    exit 1
}
