#!/usr/bin/env bash
# =============================================================================
# Citadel Access Contracts — Import Existing Resources
#
# Imports APIM resources that already exist (e.g., from a previous onboarding
# run whose state was lost, or resources created out-of-band) into this
# module's Terraform state, so they are updated rather than recreated.
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

# --- Extract a field from a named HCL object block in the tfvars file ---
# get_block_field <block_name> <field_name>
get_block_field() {
  awk -v block="$1" -v field="$2" '
    $0 ~ "^[[:space:]]*"block"[[:space:]]*=[[:space:]]*{" { inblock=1; next }
    inblock && $0 ~ "^[[:space:]]*}" { inblock=0 }
    inblock && $0 ~ "^[[:space:]]*"field"[[:space:]]*=" {
      line=$0
      sub(/.*=[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      print line
      exit
    }
  ' "$VAR_FILE"
}

SUBSCRIPTION_ID=$(get_block_field "apim" "subscription_id")
RESOURCE_GROUP=$(get_block_field "apim" "resource_group_name")
APIM_NAME=$(get_block_field "apim" "name")

BUSINESS_UNIT=$(get_block_field "use_case" "business_unit")
USE_CASE_NAME=$(get_block_field "use_case" "use_case_name")
ENVIRONMENT=$(get_block_field "use_case" "environment")

if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" || -z "$APIM_NAME" ]]; then
  error "Could not extract apim.subscription_id / resource_group_name / name from $VAR_FILE"
fi
if [[ -z "$BUSINESS_UNIT" || -z "$USE_CASE_NAME" || -z "$ENVIRONMENT" ]]; then
  error "Could not extract use_case.business_unit / use_case_name / environment from $VAR_FILE"
fi

POSTFIX="${BUSINESS_UNIT}-${USE_CASE_NAME}-${ENVIRONMENT}"
APIM_BASE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"

info "Checking for existing resources to import..."
info "  APIM:     ${APIM_NAME} in ${RESOURCE_GROUP}"
info "  Use case: ${POSTFIX}"

# --- Service codes (within the services = [...] block) ---
SERVICE_CODES=$(grep -E '^[[:space:]]*code[[:space:]]*=' "$VAR_FILE" | sed 's/.*= *"\([^"]*\)".*/\1/' || true)

if [[ -z "$SERVICE_CODES" ]]; then
  warn "No service codes found in $VAR_FILE — nothing to import."
  exit 0
fi

IMPORTED=0
SKIPPED=0
NOT_FOUND=0

# --- Helper: try to import a resource if it exists in Azure but not in state ---
try_import() {
  local tf_address="$1"
  local azure_id="$2"

  if terraform state show "$tf_address" &>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if az rest --method GET --url "https://management.azure.com${azure_id}?api-version=2024-05-01" &>/dev/null; then
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

for code in $SERVICE_CODES; do
  [[ -z "$code" ]] && continue

  PRODUCT_ID="${code}-${POSTFIX}"
  SUB_NAME="${code}-${POSTFIX}-SUB-01"

  # Product
  try_import \
    "azurerm_api_management_product.service[\"${code}\"]" \
    "${APIM_BASE_ID}/products/${PRODUCT_ID}"

  # Product policy
  try_import \
    "azurerm_api_management_product_policy.service[\"${code}\"]" \
    "${APIM_BASE_ID}/products/${PRODUCT_ID}/policies/policy"

  # Subscription
  try_import \
    "azurerm_api_management_subscription.service[\"${code}\"]" \
    "${APIM_BASE_ID}/subscriptions/${SUB_NAME}"

  # Product → API links (discover the APIs already attached to the product)
  PRODUCT_APIS=$(az rest --method GET \
    --url "https://management.azure.com${APIM_BASE_ID}/products/${PRODUCT_ID}/apis?api-version=2024-05-01" \
    2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for a in data.get('value', []):
        print(a['name'])
except Exception:
    pass
" 2>/dev/null || true)

  for api_name in $PRODUCT_APIS; do
    [[ -z "$api_name" ]] && continue
    try_import \
      "azurerm_api_management_product_api.service[\"${code}-${api_name}\"]" \
      "${APIM_BASE_ID}/products/${PRODUCT_ID}/apis/${api_name}"
  done
done

# --- Summary ---
echo ""
if [[ $IMPORTED -gt 0 ]]; then
  success "Import complete: ${IMPORTED} imported, ${SKIPPED} already in state, ${NOT_FOUND} not found in Azure."
else
  info "No imports needed: ${SKIPPED} already in state, ${NOT_FOUND} not found in Azure."
fi
