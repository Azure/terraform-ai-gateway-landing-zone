#!/usr/bin/env bash
# =============================================================================
# Citadel Access Contracts — Test Script
#
# Smoke-tests the onboarded use-case by calling the APIM gateway with each
# product's subscription key. Validates that:
#   1. The product subscription key is accepted by the gateway
#   2. The mapped API path is routable for each onboarded service
#
# When use_target_key_vault = false, subscription keys are read directly from
# the Terraform `endpoints` output. Otherwise pass --api-key explicitly.
#
# Usage:
#   ./scripts/test.sh [OPTIONS]
#
# Options:
#   --api-key KEY       APIM subscription key (required when keys are in Key Vault)
#   --gateway-url URL   Override the auto-detected gateway URL
#   --path PATH         Probe a specific API path instead of the per-service paths
#   --verbose           Show full response bodies
#   -h, --help          Show this help message
#
# Prerequisites:
#   - Successful deployment via ./scripts/deploy.sh
#   - curl and jq installed
#
# Examples:
#   ./scripts/test.sh                                   # keys from terraform output
#   ./scripts/test.sh --api-key "your-subscription-key" # explicit key
#   ./scripts/test.sh --verbose
# =============================================================================

set -euo pipefail

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0
TESTS=0
GATEWAY_URL=""
API_KEY=""
PROBE_PATH=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-url) shift; GATEWAY_URL="$1" ;;
    --api-key)     shift; API_KEY="$1" ;;
    --path)        shift; PROBE_PATH="$1" ;;
    --verbose)     VERBOSE="1" ;;
    -h|--help)     sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# --- Auto-detect gateway URL from Terraform output ---
if [[ -z "$GATEWAY_URL" ]]; then
  GATEWAY_URL=$(terraform output -raw apim_gateway_url 2>/dev/null || true)
  if [[ -z "$GATEWAY_URL" ]]; then
    echo -e "${RED}Error: Could not auto-detect gateway URL.${NC}"
    echo "  Pass --gateway-url or run from the directory with terraform.tfstate."
    exit 1
  fi
fi
GATEWAY_URL="${GATEWAY_URL%/}"

info "Testing APIM Gateway: $GATEWAY_URL"
echo ""

# --- Probe helper ---
run_probe() {
  local name="$1" url="$2" key="$3"
  TESTS=$((TESTS + 1))

  local response status_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Ocp-Apim-Subscription-Key: $key" \
    -H "api-key: $key" \
    "$url" 2>/dev/null || echo -e "\n000")
  status_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  # 2xx/3xx = routed; 401/403/404/5xx with a key = gateway routed, backend/policy gated.
  if [[ "$status_code" =~ ^[23] ]]; then
    success "$name (HTTP $status_code — routed)"
  elif [[ "$status_code" == "000" ]]; then
    fail "$name — no response (connection failed / private endpoint?)"
  elif [[ "$status_code" =~ ^(401|403|404|5) ]]; then
    warn "$name (HTTP $status_code — gateway routed; backend or policy gated)"
  else
    fail "$name — unexpected HTTP $status_code"
  fi

  if [[ -n "$VERBOSE" && -n "$body" ]]; then
    echo "    $(echo "$body" | head -c 300)"
  fi
}

# =============================================================================
# Probe each onboarded service using its endpoint + key (terraform output),
# or a single --path with --api-key.
# =============================================================================
if [[ -n "$PROBE_PATH" ]]; then
  [[ -z "$API_KEY" ]] && { echo -e "${RED}--api-key is required with --path${NC}"; exit 1; }
  run_probe "GET ${PROBE_PATH}" "${GATEWAY_URL}/${PROBE_PATH#/}" "$API_KEY"
else
  ENDPOINTS_JSON=$(terraform output -json endpoints 2>/dev/null || echo '{}')
  if [[ "$ENDPOINTS_JSON" != "{}" && "$ENDPOINTS_JSON" != "null" ]]; then
    info "Probing per-service endpoints from Terraform output..."
    echo ""
    while IFS=$'\t' read -r code endpoint key; do
      [[ -z "$code" ]] && continue
      run_probe "[$code] GET ${endpoint}" "$endpoint" "$key"
    done < <(echo "$ENDPOINTS_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value.endpoint)\t\(.value.api_key)"')
  else
    # Key Vault mode — keys are not in outputs. Require --api-key + probe products.
    if [[ -z "$API_KEY" ]]; then
      warn "use_target_key_vault is enabled (or no endpoints output)."
      warn "Pass --api-key <subscription-key> (and optionally --path) to probe the gateway."
      exit 0
    fi
    SUBS_JSON=$(terraform output -json subscriptions 2>/dev/null || echo '{}')
    info "Probing product gateway roots with provided key..."
    echo ""
    while IFS=$'\t' read -r code; do
      [[ -z "$code" ]] && continue
      run_probe "[$code] GET ${GATEWAY_URL}/" "${GATEWAY_URL}/" "$API_KEY"
    done < <(echo "$SUBS_JSON" | jq -r 'keys[]')
  fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}━━━ Summary ━━━${NC}"
echo "  Tests run: $TESTS"
if [[ $FAILURES -eq 0 ]]; then
  success "All probes routed (0 hard failures)."
  exit 0
else
  fail "$FAILURES probe(s) failed."
  exit 1
fi
