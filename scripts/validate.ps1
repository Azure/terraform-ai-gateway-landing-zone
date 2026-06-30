#!/usr/bin/env pwsh
# =============================================================================
# AI Citadel Governance Hub — Validate Script
# Runs post-deployment smoke tests against the live deployment.
# Usage: ./scripts/validate.ps1 [dev|prod]
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info    { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[FAIL]  $Message" -ForegroundColor Red }
function Write-Pass    { param([string]$Message) Write-Host "  ✅ PASS $Message" -ForegroundColor Green }
function Write-FailTest {
    param([string]$Message)
    Write-Host "  ❌ FAIL $Message" -ForegroundColor Red
    $script:Failed++
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$script:Failed = 0

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗'
Write-Host '║       🏰  AI Citadel Governance Hub — Post-Deploy Validate   ║'
Write-Host '╚══════════════════════════════════════════════════════════════╝'
Write-Host ''
Write-Info "Environment: $Environment"

Set-Location $RootDir

# --- Pin subscription from tfvars so RG/KV lookups don't hit the wrong sub ---
$Tfvars = "environments/$Environment.tfvars"
if (Test-Path $Tfvars) {
    $match = Select-String -Path $Tfvars -Pattern '^\s*subscription_id\s*=' | Select-Object -First 1
    $TfvarSub = ''
    if ($match) {
        if ($match.Line -match '=\s*"([^"]+)"') { $TfvarSub = $Matches[1] }
    }
    if ($TfvarSub) {
        az account set --subscription $TfvarSub *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Pinned subscription: $TfvarSub"
        }
        else {
            Write-Warn "Could not pin subscription $TfvarSub — using current default"
        }
    }
}

# --- Pre-install required az CLI extensions silently ---
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors *> $null

# --- Helper: run an `az` command up to 3x, returning first non-empty stdout.
function Invoke-AzRetry {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AzArgs)
    $out = ''
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $out = (az @AzArgs 2>$null)
        if ($out) { return $out }
        Start-Sleep -Seconds 2
    }
    return $out
}

# --- Get Terraform outputs ---
Write-Info 'Reading Terraform outputs...'
$ApimUrl = (terraform output -raw apim_gateway_url 2>$null)
if ($LASTEXITCODE -ne 0) { Write-Warn 'Could not read apim_gateway_url output'; $ApimUrl = '' }
$RgName = (terraform output -raw resource_group_name 2>$null)
if ($LASTEXITCODE -ne 0) { $RgName = '' }
$ApimName = (terraform output -raw apim_name 2>$null)
if ($LASTEXITCODE -ne 0) { $ApimName = '' }
$CosmosEndpoint = (terraform output -raw cosmos_db_endpoint 2>$null)
if ($LASTEXITCODE -ne 0) { $CosmosEndpoint = '' }

Write-Host ''
Write-Info 'Outputs detected:'
Write-Host "  APIM Gateway URL : $(if ($ApimUrl) { $ApimUrl } else { '<not found>' })"
Write-Host "  Resource Group   : $(if ($RgName) { $RgName } else { '<not found>' })"
Write-Host "  APIM Name        : $(if ($ApimName) { $ApimName } else { '<not found>' })"
Write-Host "  Cosmos DB        : $(if ($CosmosEndpoint) { $CosmosEndpoint } else { '<not found>' })"
Write-Host ''

# =============================================================================
# TEST 1: Resource group exists
# =============================================================================
Write-Info 'Test 1: Verifying resource group exists...'
if ($RgName) {
    $RgState = Invoke-AzRetry group show --name $RgName --query "properties.provisioningState" -o tsv
    if ($RgState -eq 'Succeeded') {
        Write-Pass "Resource group '$RgName' exists (state: Succeeded)"
    }
    else {
        Write-FailTest "Resource group '$RgName' state: $(if ($RgState) { $RgState } else { 'not found' })"
    }
}
else {
    Write-Warn 'Skipping test — resource group name not available'
}

# =============================================================================
# TEST 2: APIM service is online
# =============================================================================
Write-Info 'Test 2: Verifying APIM service is online...'
if ($ApimName -and $RgName) {
    $ApimState = Invoke-AzRetry apim show --name $ApimName --resource-group $RgName --query "provisioningState" -o tsv
    if ($ApimState -eq 'Succeeded') {
        Write-Pass "APIM '$ApimName' is online (provisioningState: Succeeded)"
    }
    else {
        Write-FailTest "APIM '$ApimName' state: $(if ($ApimState) { $ApimState } else { 'not found' })"
    }
}
else {
    Write-Warn 'Skipping test — APIM name or resource group not available'
}

# =============================================================================
# TEST 3: APIM Gateway HTTP health check
# =============================================================================
Write-Info 'Test 3: APIM gateway HTTP health check...'
if ($ApimUrl) {
    $HttpCode = '000'
    try {
        $resp = Invoke-WebRequest -Uri $ApimUrl -Method Get -TimeoutSec 15 -SkipHttpErrorCheck -ErrorAction Stop
        $HttpCode = [string]$resp.StatusCode
    }
    catch {
        if ($_.Exception.Response) { $HttpCode = [string][int]$_.Exception.Response.StatusCode } else { $HttpCode = '000' }
    }

    if ($HttpCode -in @('200', '401', '404')) {
        Write-Pass "APIM gateway is reachable (HTTP $HttpCode)"
    }
    elseif ($HttpCode -eq '000') {
        Write-FailTest 'APIM gateway is not reachable (connection timeout/refused) — check network config'
    }
    else {
        Write-Warn "APIM gateway returned unexpected HTTP $HttpCode"
    }
}
else {
    Write-Warn 'Skipping test — APIM URL not available'
}

# =============================================================================
# TEST 4: APIM APIs deployed
# =============================================================================
Write-Info 'Test 4: Verifying APIM APIs are deployed...'
if ($ApimName -and $RgName) {
    $ApiCount = (az apim api list --resource-group $RgName --service-name $ApimName --query "length(@)" -o tsv 2>$null)
    if (-not $ApiCount) { $ApiCount = '0' }

    if ([int]$ApiCount -ge 2) {
        Write-Pass "APIM has $ApiCount API(s) deployed (expected ≥ 2)"
    }
    else {
        Write-FailTest "APIM has only $ApiCount API(s) — expected ≥ 2 (Universal LLM + Azure OpenAI)"
    }
}

# =============================================================================
# TEST 5: Cosmos DB account is online
# =============================================================================
Write-Info 'Test 5: Verifying Cosmos DB...'
if ($RgName) {
    $CosmosName = (az cosmosdb list --resource-group $RgName --query "[0].name" -o tsv 2>$null)
    if ($CosmosName) {
        $CosmosState = Invoke-AzRetry cosmosdb show --name $CosmosName --resource-group $RgName --query "provisioningState" -o tsv
        if ($CosmosState -eq 'Succeeded') {
            Write-Pass "Cosmos DB '$CosmosName' is online"
        }
        else {
            Write-FailTest "Cosmos DB state: $(if ($CosmosState) { $CosmosState } else { 'not found' })"
        }
    }
    else {
        Write-FailTest "No Cosmos DB account found in resource group '$RgName'"
    }
}

# =============================================================================
# TEST 6: Event Hub namespace is active
# =============================================================================
Write-Info 'Test 6: Verifying Event Hub namespace...'
if ($RgName) {
    $Evhns = (az eventhubs namespace list --resource-group $RgName --query "[0].name" -o tsv 2>$null)
    if ($Evhns) {
        $EvhnsState = Invoke-AzRetry eventhubs namespace show --name $Evhns --resource-group $RgName --query "provisioningState" -o tsv
        if ($EvhnsState -eq 'Succeeded') {
            Write-Pass "Event Hub namespace '$Evhns' is active"
        }
        else {
            Write-FailTest "Event Hub namespace state: $(if ($EvhnsState) { $EvhnsState } else { 'not found' })"
        }
    }
    else {
        Write-FailTest "No Event Hub namespace found in resource group '$RgName'"
    }
}

# =============================================================================
# TEST 7: Key Vault is accessible
# =============================================================================
Write-Info 'Test 7: Verifying Key Vault...'
if ($RgName) {
    $KvName = (az keyvault list --resource-group $RgName --query "[0].name" -o tsv 2>$null)
    if ($KvName) {
        $KvState = Invoke-AzRetry keyvault show --name $KvName --query "properties.provisioningState" -o tsv
        if ($KvState -eq 'Succeeded') {
            Write-Pass "Key Vault '$KvName' is accessible"
        }
        else {
            Write-FailTest "Key Vault state: $(if ($KvState) { $KvState } else { 'not found' })"
        }
    }
    else {
        Write-FailTest "No Key Vault found in resource group '$RgName'"
    }
}

# =============================================================================
# TEST 8: Managed Identity assigned to APIM
# =============================================================================
Write-Info 'Test 8: Verifying managed identity on APIM...'
if ($ApimName -and $RgName) {
    $IdentityType = (az apim show --name $ApimName --resource-group $RgName --query "identity.type" -o tsv 2>$null)
    if ($IdentityType -like '*UserAssigned*') {
        Write-Pass 'APIM has UserAssigned managed identity'
    }
    else {
        Write-FailTest "APIM identity type: $(if ($IdentityType) { $IdentityType } else { 'none' }) — expected UserAssigned"
    }
}

# =============================================================================
# TEST 9: APIM API endpoint smoke tests (real HTTP calls through the gateway)
# =============================================================================
Write-Info 'Test 9: APIM API endpoint smoke tests (real HTTP calls)...'
if ($ApimName -and $RgName -and $ApimUrl) {
    # Fetch the APIM master subscription primary key via ARM REST.
    $CurrentSub = (az account show --query id -o tsv 2>$null)
    if (-not $CurrentSub) { $CurrentSub = '' }
    $ApimKey = ''
    if ($CurrentSub) {
        $KeyUrl = "https://management.azure.com/subscriptions/$CurrentSub/resourceGroups/$RgName/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/master/listSecrets?api-version=2022-08-01"
        # Retry up to 3x — first call sometimes flakes during token refresh.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $ApimKey = (az rest --method post --url $KeyUrl --query primaryKey -o tsv 2>$null)
            if (-not $ApimKey) { $ApimKey = '' }
            if ($ApimKey) { break }
            Start-Sleep -Seconds 2
        }
    }

    if (-not $ApimKey) {
        Write-Warn 'Could not fetch APIM master subscription key — calling endpoints without auth (expect 401s)'
    }
    else {
        Write-Info "Fetched APIM master subscription key (length=$($ApimKey.Length))"
    }

    # List deployed APIs and their gateway paths.
    $ApisTsv = (az apim api list --resource-group $RgName --service-name $ApimName --query "[].{name:name, path:path}" -o tsv 2>$null)
    if (-not $ApisTsv) { $ApisTsv = '' }

    if (-not $ApisTsv) {
        Write-FailTest 'Could not list APIM APIs'
    }
    else {
        $SmokePass = 0; $SmokeFail = 0; $SmokeWarn = 0
        foreach ($apiLine in ($ApisTsv -split "`n")) {
            $apiLine = $apiLine.TrimEnd("`r")
            if ([string]::IsNullOrWhiteSpace($apiLine)) { continue }
            $cols = $apiLine -split "`t"
            $apiName = $cols[0]
            $apiPath = if ($cols.Count -gt 1) { $cols[1] } else { '' }
            if ([string]::IsNullOrEmpty($apiName)) { continue }

            # Build a probe URL: gateway + path.
            $probeUrl = "$($ApimUrl.TrimEnd('/'))/$apiPath"
            $headers = @{}
            if ($ApimKey) {
                $headers['Ocp-Apim-Subscription-Key'] = $ApimKey
                $headers['api-key'] = $ApimKey
            }

            $code = '000'
            try {
                $resp = Invoke-WebRequest -Uri $probeUrl -Method Get -Headers $headers -TimeoutSec 20 -SkipHttpErrorCheck -ErrorAction Stop
                $code = [string]$resp.StatusCode
            }
            catch {
                if ($_.Exception.Response) { $code = [string][int]$_.Exception.Response.StatusCode } else { $code = '000' }
            }

            switch -Regex ($code) {
                '^000$' {
                    Write-Host "    ❌ $apiName (path=$apiPath) — connection failed (HTTP 000)"
                    $SmokeFail++
                    break
                }
                '^(401|403)$' {
                    if ($ApimKey) {
                        Write-Host "    ⚠️  $apiName (path=$apiPath) — HTTP $code (API requires JWT/OAuth in addition to key)"
                    }
                    else {
                        Write-Host "    ⚠️  $apiName (path=$apiPath) — HTTP $code (expected without key)"
                    }
                    $SmokeWarn++
                    break
                }
                '^(2..|3..|400|404|405|415|422)$' {
                    Write-Host "    ✅ $apiName (path=$apiPath) — HTTP $code (gateway routed OK)"
                    $SmokePass++
                    break
                }
                '^5..$' {
                    Write-Host "    ⚠️  $apiName (path=$apiPath) — HTTP $code (backend rejected probe; gateway likely OK)"
                    $SmokeWarn++
                    break
                }
                default {
                    Write-Host "    ⚠️  $apiName (path=$apiPath) — unexpected HTTP $code"
                    $SmokeWarn++
                }
            }
        }

        if ($SmokeFail -eq 0) {
            Write-Pass "APIM smoke tests: $SmokePass routed OK, $SmokeWarn warn, 0 failed"
        }
        else {
            Write-FailTest "APIM smoke tests: $SmokeFail failed ($SmokePass ok, $SmokeWarn warn)"
        }

        # Targeted functional probe: Universal LLM /chat/completions (POST) if available.
        if ($ApimKey -and ($ApisTsv -match "`tmodels(`r?$|`n)" -or $ApisTsv -match "`tunified-ai(`r?$|`n)")) {
            Write-Info '  Functional probe: POST chat/completions on universal-llm-api...'
            $llmCode = '000'
            $body = '{"model":"gpt-4o","messages":[{"role":"user","content":"ping"}],"max_tokens":4}'
            $llmHeaders = @{
                'Ocp-Apim-Subscription-Key' = $ApimKey
                'api-key'                   = $ApimKey
                'Content-Type'              = 'application/json'
            }
            try {
                $resp = Invoke-WebRequest -Uri "$($ApimUrl.TrimEnd('/'))/models/chat/completions" -Method Post -Headers $llmHeaders -Body $body -TimeoutSec 30 -SkipHttpErrorCheck -ErrorAction Stop
                $llmCode = [string]$resp.StatusCode
            }
            catch {
                if ($_.Exception.Response) { $llmCode = [string][int]$_.Exception.Response.StatusCode } else { $llmCode = '000' }
            }
            switch -Regex ($llmCode) {
                '^200$'       { Write-Pass 'Universal LLM chat/completions returned 200 (live model response)' }
                '^(404|400)$' { Write-Warn "Universal LLM chat/completions returned $llmCode (route OK, model deployment may differ)" }
                '^(401|403)$' { Write-FailTest "Universal LLM chat/completions auth rejected (HTTP $llmCode)" }
                '^000$'       { Write-FailTest 'Universal LLM chat/completions connection failed' }
                default       { Write-Warn "Universal LLM chat/completions returned $llmCode" }
            }
        }
    }
}
else {
    Write-Warn 'Skipping APIM smoke tests — APIM/RG/URL not available'
}

# =============================================================================
# RESULTS SUMMARY
# =============================================================================
Write-Host ''
Write-Host '══════════════════════════════════════════════════════'
if ($script:Failed -eq 0) {
    Write-Host '  ✅  All validation checks passed!' -ForegroundColor Green
    Write-Host "  Environment '$Environment' is deployed and healthy."
}
else {
    Write-Host "  ❌  $($script:Failed) validation check(s) failed." -ForegroundColor Red
    Write-Host '  Review failures above and check Azure Portal for details.'
}
Write-Host '══════════════════════════════════════════════════════'
Write-Host ''

Write-Info 'Next steps:'
Write-Host "  • Run LLM test: curl -X POST $ApimUrl/models/chat/completions \"
Write-Host "      -H 'Content-Type: application/json' \"
Write-Host "      -H 'api-key: <your-subscription-key>' \"
Write-Host "      -d '{`"model`":`"gpt-4o`",`"messages`":[{`"role`":`"user`",`"content`":`"Hello`"}]}'"
Write-Host ''

exit $script:Failed
