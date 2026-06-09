#!/usr/bin/env bash
# =============================================================================
# LLM Backend Onboarding — Import Existing Resources
#
# Imports Azure resources that already exist (e.g., from the main Citadel
# deployment) into this module's Terraform state. This enables the onboarding
# module to update resources that were initially created by the main deployment.
#
# Usage:
#   ./scripts/import-existing.sh [--var-file FILE]
#
# Called automatically by deploy.sh before plan/apply.
# =============================================================================

set -euo pipefail

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Parse arguments ---
VAR_FILE="terraform.tfvars"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file) shift; VAR_FILE="$1" ;;
    *) ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# --- Extract key variables from tfvars ---
get_tf_var() {
  grep -E "^\s*$1\s*=" "$VAR_FILE" | head -1 | sed 's/.*= *"\(.*\)".*/\1/'
}

SUBSCRIPTION_ID=$(get_tf_var "subscription_id")
RESOURCE_GROUP=$(get_tf_var "resource_group_name")
APIM_NAME=$(get_tf_var "apim_name")

if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" || -z "$APIM_NAME" ]]; then
  error "Could not extract subscription_id, resource_group_name, or apim_name from $VAR_FILE"
fi

APIM_BASE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"

info "Checking for existing resources to import..."
info "  APIM: ${APIM_NAME} in ${RESOURCE_GROUP}"

IMPORTED=0
SKIPPED=0
NOT_FOUND=0

# --- Helper: try to import a resource if it exists in Azure but not in state ---
try_import() {
  local tf_address="$1"
  local azure_id="$2"

  # Check if already in Terraform state
  if terraform state show "$tf_address" &>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  # Check if resource exists in Azure
  if az rest --method GET --url "https://management.azure.com${azure_id}?api-version=2024-06-01-preview" &>/dev/null; then
    info "  Importing: $tf_address"
    if terraform import -var-file="$VAR_FILE" "$tf_address" "$azure_id" &>/dev/null; then
      success "  Imported: $tf_address"
      IMPORTED=$((IMPORTED + 1))
    else
      warn "  Failed to import: $tf_address (will be recreated)"
    fi
  else
    NOT_FOUND=$((NOT_FOUND + 1))
  fi
}

# --- Import LLM Backends ---
# Extract backend_ids from tfvars (macOS-compatible)
BACKEND_IDS=$(grep 'backend_id' "$VAR_FILE" | sed 's/.*= *"\([^"]*\)".*/\1/' || true)

for backend_id in $BACKEND_IDS; do
  try_import \
    "azapi_resource.llm_backend[\"${backend_id}\"]" \
    "${APIM_BASE_ID}/backends/${backend_id}"
done

# --- Import Dynamic Policy Fragments ---
DYNAMIC_FRAGMENTS=("set-backend-pools" "get-available-models" "metadata-config")
TF_DYNAMIC_NAMES=("set_backend_pools" "get_available_models" "metadata_config")

for i in "${!DYNAMIC_FRAGMENTS[@]}"; do
  try_import \
    "azurerm_api_management_policy_fragment.${TF_DYNAMIC_NAMES[$i]}" \
    "${APIM_BASE_ID}/policyFragments/${DYNAMIC_FRAGMENTS[$i]}"
done

# --- Import Static Policy Fragments ---
STATIC_FRAGMENTS=("set-backend-authorization" "set-target-backend-pool" "set-llm-requested-model" "set-llm-usage" "validate-model-access" "responses-id-security" "responses-id-cache-store")

for frag in "${STATIC_FRAGMENTS[@]}"; do
  try_import \
    "azurerm_api_management_policy_fragment.static[\"${frag}\"]" \
    "${APIM_BASE_ID}/policyFragments/${frag}"
done

# --- Import resolve-model-alias Policy Fragment (own resource block) ---
try_import \
  "azurerm_api_management_policy_fragment.resolve_model_alias" \
  "${APIM_BASE_ID}/policyFragments/resolve-model-alias"

# --- Import AWS Bedrock Named Values (always created with safe defaults) ---
AWS_NAMED_VALUES=("aws-access-key" "aws-secret-key" "aws-region")
TF_AWS_NAMES=("aws_access_key" "aws_secret_key" "aws_region")

for i in "${!AWS_NAMED_VALUES[@]}"; do
  try_import \
    "azurerm_api_management_named_value.${TF_AWS_NAMES[$i]}" \
    "${APIM_BASE_ID}/namedValues/${AWS_NAMED_VALUES[$i]}"
done

# --- Import Dynamic Backend API-Key Named Values ---
# Derived from auth_config.named_value_key entries in the tfvars file.
NAMED_VALUE_KEYS=$(grep -E 'named_value_key' "$VAR_FILE" | sed 's/.*= *"\([^"]*\)".*/\1/' || true)

for nv_key in $NAMED_VALUE_KEYS; do
  [[ -z "$nv_key" ]] && continue
  try_import \
    "azurerm_api_management_named_value.backend_api_key[\"${nv_key}\"]" \
    "${APIM_BASE_ID}/namedValues/${nv_key}"
done

# --- Import Backend Pools (if any exist) ---
# Pool names are derived from model names — check common patterns
POOL_NAMES=$(az rest --method GET \
  --url "https://management.azure.com${APIM_BASE_ID}/backends?api-version=2024-06-01-preview" \
  2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for b in data.get('value', []):
        props = b.get('properties', {})
        if props.get('type') == 'Pool':
            print(b['name'])
except: pass
" 2>/dev/null || true)

for pool_name in $POOL_NAMES; do
  try_import \
    "azapi_resource.llm_backend_pool[\"${pool_name}\"]" \
    "${APIM_BASE_ID}/backends/${pool_name}"
done

# --- Summary ---
echo ""
if [[ $IMPORTED -gt 0 ]]; then
  success "Import complete: ${IMPORTED} imported, ${SKIPPED} already in state, ${NOT_FOUND} not found in Azure."
else
  info "No imports needed: ${SKIPPED} already in state, ${NOT_FOUND} not found in Azure."
fi
