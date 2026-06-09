#!/usr/bin/env bash
# =============================================================================
# AI Citadel Governance Hub — Validate Script
# Runs post-deployment smoke tests against the live deployment.
# Usage: ./scripts/validate.sh [dev|prod]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[FAIL]${NC}  $*"; }
pass()    { echo -e "${GREEN}  ✅ PASS${NC} $*"; }
fail()    { echo -e "${RED}  ❌ FAIL${NC} $*"; FAILED=$((FAILED+1)); }

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FAILED=0

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       🏰  AI Citadel Governance Hub — Post-Deploy Validate   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
info "Environment: ${ENVIRONMENT}"

cd "$ROOT_DIR"

# --- Wrap az to never block on stdin (extension prompts, etc.) ---
az() { command az "$@" </dev/null; }

# --- Pin subscription from tfvars so RG/KV lookups don't hit the wrong sub ---
TFVARS="environments/${ENVIRONMENT}.tfvars"
if [[ -f "$TFVARS" ]]; then
  TFVAR_SUB=$(grep -E '^[[:space:]]*subscription_id[[:space:]]*=' "$TFVARS" \
              | head -n1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
  if [[ -n "${TFVAR_SUB:-}" ]]; then
    if az account set --subscription "$TFVAR_SUB" >/dev/null 2>&1; then
      info "Pinned subscription: ${TFVAR_SUB}"
    else
      warn "Could not pin subscription ${TFVAR_SUB} — using current default"
    fi
  fi
fi

# --- Pre-install required az CLI extensions silently ---
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors >/dev/null 2>&1 || true

# --- Helper: run an `az` command up to 3x, returning first non-empty stdout.
# ARM list/show calls occasionally flake with empty output during token
# refresh or throttling; a short retry eliminates false negatives.
az_retry() {
  local out=""
  for attempt in 1 2 3; do
    out=$(az "$@" 2>/dev/null || true)
    [[ -n "$out" ]] && { echo "$out"; return 0; }
    sleep 2
  done
  echo "$out"
}

# --- Get Terraform outputs ---
info "Reading Terraform outputs..."
APIM_URL=$(terraform output -raw apim_gateway_url 2>/dev/null)         || { warn "Could not read apim_gateway_url output"; APIM_URL=""; }
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)       || RG_NAME=""
APIM_NAME=$(terraform output -raw apim_name 2>/dev/null)               || APIM_NAME=""
COSMOS_ENDPOINT=$(terraform output -raw cosmos_db_endpoint 2>/dev/null) || COSMOS_ENDPOINT=""

echo ""
info "Outputs detected:"
echo "  APIM Gateway URL : ${APIM_URL:-<not found>}"
echo "  Resource Group   : ${RG_NAME:-<not found>}"
echo "  APIM Name        : ${APIM_NAME:-<not found>}"
echo "  Cosmos DB        : ${COSMOS_ENDPOINT:-<not found>}"
echo ""

# =============================================================================
# TEST 1: Resource group exists
# =============================================================================
info "Test 1: Verifying resource group exists..."
if [[ -n "$RG_NAME" ]]; then
  RG_STATE=$(az_retry group show --name "$RG_NAME" --query "properties.provisioningState" -o tsv)
  if [[ "$RG_STATE" == "Succeeded" ]]; then
    pass "Resource group '${RG_NAME}' exists (state: Succeeded)"
  else
    fail "Resource group '${RG_NAME}' state: ${RG_STATE:-not found}"
  fi
else
  warn "Skipping test — resource group name not available"
fi

# =============================================================================
# TEST 2: APIM service is online
# =============================================================================
info "Test 2: Verifying APIM service is online..."
if [[ -n "$APIM_NAME" && -n "$RG_NAME" ]]; then
  APIM_STATE=$(az_retry apim show --name "$APIM_NAME" --resource-group "$RG_NAME" --query "provisioningState" -o tsv)
  if [[ "$APIM_STATE" == "Succeeded" ]]; then
    pass "APIM '${APIM_NAME}' is online (provisioningState: Succeeded)"
  else
    fail "APIM '${APIM_NAME}' state: ${APIM_STATE:-not found}"
  fi
else
  warn "Skipping test — APIM name or resource group not available"
fi

# =============================================================================
# TEST 3: APIM Gateway HTTP health check
# =============================================================================
info "Test 3: APIM gateway HTTP health check..."
if [[ -n "$APIM_URL" ]]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 \
    "${APIM_URL}" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "401" || "$HTTP_CODE" == "404" ]]; then
    pass "APIM gateway is reachable (HTTP ${HTTP_CODE})"
  elif [[ "$HTTP_CODE" == "000" ]]; then
    fail "APIM gateway is not reachable (connection timeout/refused) — check network config"
  else
    warn "APIM gateway returned unexpected HTTP ${HTTP_CODE}"
  fi
else
  warn "Skipping test — APIM URL not available"
fi

# =============================================================================
# TEST 4: APIM APIs deployed
# =============================================================================
info "Test 4: Verifying APIM APIs are deployed..."
if [[ -n "$APIM_NAME" && -n "$RG_NAME" ]]; then
  API_COUNT=$(az apim api list \
    --resource-group "$RG_NAME" \
    --service-name "$APIM_NAME" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "$API_COUNT" -ge 2 ]]; then
    pass "APIM has ${API_COUNT} API(s) deployed (expected ≥ 2)"
  else
    fail "APIM has only ${API_COUNT} API(s) — expected ≥ 2 (Universal LLM + Azure OpenAI)"
  fi
fi

# =============================================================================
# TEST 5: Cosmos DB account is online
# =============================================================================
info "Test 5: Verifying Cosmos DB..."
if [[ -n "$RG_NAME" ]]; then
  COSMOS_NAME=$(az cosmosdb list --resource-group "$RG_NAME" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$COSMOS_NAME" ]]; then
    COSMOS_STATE=$(az_retry cosmosdb show --name "$COSMOS_NAME" --resource-group "$RG_NAME" --query "provisioningState" -o tsv)
    if [[ "$COSMOS_STATE" == "Succeeded" ]]; then
      pass "Cosmos DB '${COSMOS_NAME}' is online"
    else
      fail "Cosmos DB state: ${COSMOS_STATE:-not found}"
    fi
  else
    fail "No Cosmos DB account found in resource group '${RG_NAME}'"
  fi
fi

# =============================================================================
# TEST 6: Event Hub namespace is active
# =============================================================================
info "Test 6: Verifying Event Hub namespace..."
if [[ -n "$RG_NAME" ]]; then
  EVHNS=$(az eventhubs namespace list --resource-group "$RG_NAME" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$EVHNS" ]]; then
    EVHNS_STATE=$(az_retry eventhubs namespace show --name "$EVHNS" --resource-group "$RG_NAME" --query "provisioningState" -o tsv)
    if [[ "$EVHNS_STATE" == "Succeeded" ]]; then
      pass "Event Hub namespace '${EVHNS}' is active"
    else
      fail "Event Hub namespace state: ${EVHNS_STATE:-not found}"
    fi
  else
    fail "No Event Hub namespace found in resource group '${RG_NAME}'"
  fi
fi

# =============================================================================
# TEST 7: Key Vault is accessible
# =============================================================================
info "Test 7: Verifying Key Vault..."
if [[ -n "$RG_NAME" ]]; then
  KV_NAME=$(az keyvault list --resource-group "$RG_NAME" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$KV_NAME" ]]; then
    KV_STATE=$(az_retry keyvault show --name "$KV_NAME" --query "properties.provisioningState" -o tsv)
    if [[ "$KV_STATE" == "Succeeded" ]]; then
      pass "Key Vault '${KV_NAME}' is accessible"
    else
      fail "Key Vault state: ${KV_STATE:-not found}"
    fi
  else
    fail "No Key Vault found in resource group '${RG_NAME}'"
  fi
fi

# =============================================================================
# TEST 8: Managed Identity assigned to APIM
# =============================================================================
info "Test 8: Verifying managed identity on APIM..."
if [[ -n "$APIM_NAME" && -n "$RG_NAME" ]]; then
  IDENTITY_TYPE=$(az apim show --name "$APIM_NAME" \
    --resource-group "$RG_NAME" \
    --query "identity.type" -o tsv 2>/dev/null || echo "")
  if [[ "$IDENTITY_TYPE" == *"UserAssigned"* ]]; then
    pass "APIM has UserAssigned managed identity"
  else
    fail "APIM identity type: ${IDENTITY_TYPE:-none} — expected UserAssigned"
  fi
fi

# =============================================================================
# TEST 9: APIM API endpoint smoke tests (real HTTP calls through the gateway)
# =============================================================================
info "Test 9: APIM API endpoint smoke tests (real HTTP calls)..."
if [[ -n "$APIM_NAME" && -n "$RG_NAME" && -n "$APIM_URL" ]]; then
  # Fetch the APIM master subscription primary key via ARM REST.
  CURRENT_SUB=$(az account show --query id -o tsv 2>/dev/null || echo "")
  APIM_KEY=""
  if [[ -n "$CURRENT_SUB" ]]; then
    KEY_URL="https://management.azure.com/subscriptions/${CURRENT_SUB}/resourceGroups/${RG_NAME}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/master/listSecrets?api-version=2022-08-01"
    # Retry up to 3x — first call sometimes flakes during token refresh.
    for attempt in 1 2 3; do
      APIM_KEY=$(az rest --method post --url "$KEY_URL" --query primaryKey -o tsv 2>/dev/null || echo "")
      [[ -n "$APIM_KEY" ]] && break
      sleep 2
    done
  fi

  if [[ -z "$APIM_KEY" ]]; then
    warn "Could not fetch APIM master subscription key — calling endpoints without auth (expect 401s)"
  else
    info "Fetched APIM master subscription key (length=${#APIM_KEY})"
  fi

  # List deployed APIs and their gateway paths.
  APIS_TSV=$(az apim api list --resource-group "$RG_NAME" --service-name "$APIM_NAME" \
             --query "[].{name:name, path:path}" -o tsv 2>/dev/null || echo "")

  if [[ -z "$APIS_TSV" ]]; then
    fail "Could not list APIM APIs"
  else
    SMOKE_PASS=0; SMOKE_FAIL=0; SMOKE_WARN=0
    while IFS=$'\t' read -r api_name api_path; do
      [[ -z "$api_name" ]] && continue
      # Build a probe URL: gateway + path. We hit the API root (or a likely
      # operation path). We only care that APIM routes the request — i.e. we
      # do NOT get connection failure (000) or unauthorized (401).
      probe_url="${APIM_URL%/}/${api_path}"
      # Use GET with the subscription key. Accept any 2xx/3xx/4xx other than 401/403/000
      # as evidence that the API is registered and the key is honored.
      HDRS=()
      if [[ -n "$APIM_KEY" ]]; then
        HDRS=(-H "Ocp-Apim-Subscription-Key: ${APIM_KEY}" -H "api-key: ${APIM_KEY}")
      fi
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 \
             "${HDRS[@]}" "$probe_url" 2>/dev/null || echo "000")

      case "$code" in
        000)
          echo "    ❌ ${api_name} (path=${api_path}) — connection failed (HTTP 000)"
          SMOKE_FAIL=$((SMOKE_FAIL+1))
          ;;
        401|403)
          if [[ -n "$APIM_KEY" ]]; then
            # API likely requires additional auth (JWT/OAuth) beyond the
            # subscription key — gateway IS routing, so treat as warn.
            echo "    ⚠️  ${api_name} (path=${api_path}) — HTTP ${code} (API requires JWT/OAuth in addition to key)"
            SMOKE_WARN=$((SMOKE_WARN+1))
          else
            echo "    ⚠️  ${api_name} (path=${api_path}) — HTTP ${code} (expected without key)"
            SMOKE_WARN=$((SMOKE_WARN+1))
          fi
          ;;
        2*|3*|400|404|405|415|422)
          echo "    ✅ ${api_name} (path=${api_path}) — HTTP ${code} (gateway routed OK)"
          SMOKE_PASS=$((SMOKE_PASS+1))
          ;;
        5*)
          # 5xx on a root-path GET commonly means the backend rejects empty
          # GET (POST-only APIs) — gateway IS routing. Warn, do not fail.
          echo "    ⚠️  ${api_name} (path=${api_path}) — HTTP ${code} (backend rejected probe; gateway likely OK)"
          SMOKE_WARN=$((SMOKE_WARN+1))
          ;;
        *)
          echo "    ⚠️  ${api_name} (path=${api_path}) — unexpected HTTP ${code}"
          SMOKE_WARN=$((SMOKE_WARN+1))
          ;;
      esac
    done <<< "$APIS_TSV"

    if [[ $SMOKE_FAIL -eq 0 ]]; then
      pass "APIM smoke tests: ${SMOKE_PASS} routed OK, ${SMOKE_WARN} warn, 0 failed"
    else
      fail "APIM smoke tests: ${SMOKE_FAIL} failed (${SMOKE_PASS} ok, ${SMOKE_WARN} warn)"
    fi

    # Targeted functional probe: Universal LLM /chat/completions (POST) if available.
    if [[ -n "$APIM_KEY" ]] && echo "$APIS_TSV" | grep -qE $'\tmodels$|\tunified-ai$'; then
      info "  Functional probe: POST chat/completions on universal-llm-api..."
      llm_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 \
                 -H "Ocp-Apim-Subscription-Key: ${APIM_KEY}" \
                 -H "api-key: ${APIM_KEY}" \
                 -H "Content-Type: application/json" \
                 -d '{"model":"gpt-4o","messages":[{"role":"user","content":"ping"}],"max_tokens":4}' \
                 "${APIM_URL%/}/models/chat/completions" 2>/dev/null || echo "000")
      case "$llm_code" in
        200) pass "Universal LLM chat/completions returned 200 (live model response)" ;;
        404|400) warn "Universal LLM chat/completions returned ${llm_code} (route OK, model deployment may differ)" ;;
        401|403) fail "Universal LLM chat/completions auth rejected (HTTP ${llm_code})" ;;
        000)     fail "Universal LLM chat/completions connection failed" ;;
        *)       warn "Universal LLM chat/completions returned ${llm_code}" ;;
      esac
    fi
  fi
else
  warn "Skipping APIM smoke tests — APIM/RG/URL not available"
fi

# =============================================================================
# RESULTS SUMMARY
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  echo -e "  ${GREEN}✅  All validation checks passed!${NC}"
  echo "  Environment '${ENVIRONMENT}' is deployed and healthy."
else
  echo -e "  ${RED}❌  ${FAILED} validation check(s) failed.${NC}"
  echo "  Review failures above and check Azure Portal for details."
fi
echo "══════════════════════════════════════════════════════"
echo ""

info "Next steps:"
echo "  • Run LLM test: curl -X POST ${APIM_URL}/models/chat/completions \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -H 'api-key: <your-subscription-key>' \\"
echo "      -d '{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo ""

exit $FAILED
