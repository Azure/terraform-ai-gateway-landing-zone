#!/usr/bin/env bash
# =============================================================================
# AI Citadel Governance Hub — Deploy Script
#
# Usage:
#   ./scripts/deploy.sh [ENV] [OPTIONS]
#
# Positional:
#   ENV                    dev (default) | prod
#
# Core options:
#   --auto-approve         Skip interactive confirmation
#
# Optional add-on flags (set feature-flag Terraform variables to true):
#   --with-entra           Enable Entra ID app registration add-on (§19.13)
#   --with-foundry-conn    Enable Foundry → APIM connection (§2.3)
#   --with-access-contracts
#                          Enable citadel-access-contracts products (§2.3)
#   --with-mcp-samples     Enable Weather + MS Learn MCP sample APIs
#   --with-jwt             Populate APIM JWT-* named values (implied by --with-entra)
#   --with-apic-onboarding Onboard every APIM API into API Center
#   --all-addons           Shortcut: all --with-* flags above
#
# Logic App code publish (on by default):
#   --skip-logic-app-code  Do not zip+push src/usage-ingestion-logicapp this run
#   --logic-app-code-only  Skip full apply; re-publish workflow code only
#
# Rollout mode:
#   --phased               Two-phase apply. Phase 1 = core (all add-ons forced
#                          to false). Phase 2 = re-apply with the selected
#                          --with-* flags enabled. Mirrors the Bicep
#                          "follow-on deployment" workflow.
#
# Examples:
#   ./scripts/deploy.sh dev                                     # core only
#   ./scripts/deploy.sh dev --with-entra --with-foundry-conn    # single apply
#   ./scripts/deploy.sh prod --all-addons --phased              # Bicep-style
# =============================================================================

set -euo pipefail

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Flag parsing ---
ENVIRONMENT="dev"
AUTO_APPROVE=""
PHASED=""
WITH_ENTRA=""
WITH_FOUNDRY_CONN=""
WITH_ACCESS_CONTRACTS=""
WITH_MCP_SAMPLES=""
WITH_JWT=""
WITH_APIC_ONBOARDING=""
SKIP_LOGIC_APP_CODE=""
LOGIC_APP_CODE_ONLY=""

# First positional (if not a flag) = environment
if [[ $# -gt 0 && "${1:-}" != --* ]]; then
  ENVIRONMENT="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve)          AUTO_APPROVE="1" ;;
    --phased)                PHASED="1" ;;
    --with-entra)            WITH_ENTRA="1" ;;
    --with-foundry-conn)     WITH_FOUNDRY_CONN="1" ;;
    --with-access-contracts) WITH_ACCESS_CONTRACTS="1" ;;
    --with-mcp-samples)      WITH_MCP_SAMPLES="1" ;;
    --with-jwt)              WITH_JWT="1" ;;
    --with-apic-onboarding)  WITH_APIC_ONBOARDING="1" ;;
    --skip-logic-app-code)   SKIP_LOGIC_APP_CODE="1" ;;
    --logic-app-code-only)   LOGIC_APP_CODE_ONLY="1" ;;
    --all-addons)
      WITH_ENTRA="1"; WITH_FOUNDRY_CONN="1"; WITH_ACCESS_CONTRACTS="1"
      WITH_MCP_SAMPLES="1"; WITH_JWT="1"; WITH_APIC_ONBOARDING="1" ;;
    -h|--help)
      sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) error "Unknown argument: $1 (use --help)" ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="${ROOT_DIR}/environments/${ENVIRONMENT}.tfvars"

# --- Returns -var args for the current rollout phase (one per line) ---
# $1 = phase number (0 = single shot, 1 = core phase, 2 = add-ons phase)
addon_tfargs() {
  local phase="$1"
  if [[ "$phase" == "1" ]]; then
    # Force all add-ons off for core phase
    echo "-var=enable_entra_id_setup=false"
    echo "-var=enable_foundry_apim_connection=false"
    echo "-var=enable_access_contracts=false"
    echo "-var=is_mcp_sample_deployed=false"
    echo "-var=enable_jwt_auth=false"
    echo "-var=enable_api_center_onboarding=false"
  else
    # Phase 2 or single-shot: set only the ones the user asked for
    [[ -n "$WITH_ENTRA"            ]] && echo "-var=enable_entra_id_setup=true"
    [[ -n "$WITH_FOUNDRY_CONN"     ]] && echo "-var=enable_foundry_apim_connection=true"
    [[ -n "$WITH_ACCESS_CONTRACTS" ]] && echo "-var=enable_access_contracts=true"
    [[ -n "$WITH_MCP_SAMPLES"      ]] && echo "-var=is_mcp_sample_deployed=true"
    [[ -n "$WITH_JWT"              ]] && echo "-var=enable_jwt_auth=true"
    [[ -n "$WITH_APIC_ONBOARDING"  ]] && echo "-var=enable_api_center_onboarding=true"
  fi

  # Skip workflow-code publish if requested (applies to all phases).
  if [[ -n "$SKIP_LOGIC_APP_CODE" ]]; then
    echo "-var=enable_logic_app_code_deploy=false"
  fi
}

# --- Banner ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       🏰  AI Citadel Governance Hub — Terraform Deploy       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
info "Environment : ${ENVIRONMENT}"
info "Vars file   : ${TFVARS_FILE}"
info "Working dir : ${ROOT_DIR}"
[[ -n "$AUTO_APPROVE" ]] && info "Auto-approve: Enabled"
if [[ -n "$PHASED" ]]; then info "Rollout     : phased (core → add-ons)"; else info "Rollout     : single apply"; fi
ADDONS_SUMMARY=""
[[ -n "$WITH_ENTRA"            ]] && ADDONS_SUMMARY+="entra "
[[ -n "$WITH_FOUNDRY_CONN"     ]] && ADDONS_SUMMARY+="foundry-conn "
[[ -n "$WITH_ACCESS_CONTRACTS" ]] && ADDONS_SUMMARY+="access-contracts "
[[ -n "$WITH_MCP_SAMPLES"      ]] && ADDONS_SUMMARY+="mcp-samples "
[[ -n "$WITH_JWT"              ]] && ADDONS_SUMMARY+="jwt "
[[ -n "$WITH_APIC_ONBOARDING"  ]] && ADDONS_SUMMARY+="apic-onboarding "
if [[ -n "$ADDONS_SUMMARY" ]]; then info "Add-ons     : ${ADDONS_SUMMARY}"; else info "Add-ons     : none (core only)"; fi
echo ""

# --- Pre-flight checks ---
info "Running pre-flight checks..."

command -v terraform >/dev/null 2>&1 || error "terraform not found. Install from https://developer.hashicorp.com/terraform/install"
command -v az        >/dev/null 2>&1 || error "Azure CLI not found. Install from https://aka.ms/installazurecli"

TF_VERSION=$(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || terraform version | head -1 | awk '{print $2}' | tr -d 'v')
info "Terraform version: ${TF_VERSION}"

[[ -f "$TFVARS_FILE" ]] || error "Vars file not found: ${TFVARS_FILE}"

# --- Azure login check ---
info "Verifying Azure CLI authentication..."
ACCOUNT=$(az account show --query "{name:name, id:id, user:user.name}" -o json 2>/dev/null) || error "Not logged in to Azure. Run: az login"
SUBSCRIPTION_NAME=$(echo "$ACCOUNT" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
SUBSCRIPTION_ID=$(echo "$ACCOUNT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
LOGGED_USER=$(echo "$ACCOUNT" | python3 -c "import sys,json; print(json.load(sys.stdin)['user'])")

success "Logged in as: ${LOGGED_USER}"
info "Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# --- Subscription ID check in tfvars ---
if grep -q "YOUR-SUBSCRIPTION-ID" "$TFVARS_FILE"; then
  warn "subscription_id is still set to YOUR-SUBSCRIPTION-ID in ${TFVARS_FILE}"
  warn "Auto-setting it to the current subscription: ${SUBSCRIPTION_ID}"
  sed -i.bak "s/YOUR-SUBSCRIPTION-ID/${SUBSCRIPTION_ID}/g" "$TFVARS_FILE"
  success "Updated subscription_id in ${TFVARS_FILE}"
fi

# --- Register required resource providers ---
info "Registering required Azure resource providers (this may take a minute)..."
PROVIDERS=(
  "Microsoft.AlertsManagement" "Microsoft.ApiCenter" "Microsoft.ApiManagement"
  "Microsoft.CognitiveServices" "Microsoft.DocumentDB" "Microsoft.EventHub"
  "Microsoft.Insights" "Microsoft.KeyVault" "Microsoft.Logic"
  "Microsoft.MachineLearningServices" "Microsoft.ManagedIdentity" "Microsoft.Network"
  "Microsoft.OperationalInsights" "Microsoft.Storage" "Microsoft.Web"
)

for provider in "${PROVIDERS[@]}"; do
  STATE=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
  if [[ "$STATE" == "Registered" ]]; then
    echo -e "✅  ${provider}: ${GREEN}${STATE}${NC}"
    continue
  fi
  info "Registering ${provider}..."
  REG_OUTPUT=$(az provider register --namespace "$provider" --wait 2>&1) || {
    echo -e "${RED}[ERROR]${NC} Failed to register ${provider}: ${REG_OUTPUT}"
    read -rp "Continue anyway? (y/N): " CONT
    [[ "$CONT" =~ ^[Yy]$ ]] || error "Aborted by user."
    continue
  }
  success "Registered ${provider}"
done
success "All resource providers registered."

# --- Terraform init ---
echo ""
info "Initialising Terraform..."
cd "$ROOT_DIR"
terraform init -upgrade -reconfigure
success "Terraform initialised."

# --- Terraform validate ---
info "Validating Terraform configuration..."
terraform validate && success "Configuration is valid." || error "Terraform validation failed."

# =============================================================================
# plan_and_apply <phase_label> <phase_number>
#   phase_number: 0 = single shot; 1 = core; 2 = add-ons
# =============================================================================
plan_and_apply() {
  local phase_label="$1"
  local phase="$2"

  echo ""
  echo "───────────────────────────────────────────────────────────────"
  info "Phase: ${phase_label}"
  info "This will create/modify Azure resources for the '${phase_label}' phase of the deployment."
  info "This operation usually takes up-to 10 minutes, depending on the number of resources being provisioned."
  info "The first phase (core) will deploy the baseline infrastructure. The second phase (add-ons) will apply the selected add-on features on top of the baseline."
  info "The first phase (core) may take up-to 30-45 minutes to complete."
  echo "───────────────────────────────────────────────────────────────"

  # Collect -var args
  local extra_vars=()
  while IFS= read -r v; do
    [[ -n "$v" ]] && extra_vars+=("$v")
  done < <(addon_tfargs "$phase")

  [[ ${#extra_vars[@]} -gt 0 ]] && info "Overrides: ${extra_vars[*]}"

  local PLAN_FILE="${ROOT_DIR}/.terraform/tfplan-${ENVIRONMENT}-${phase_label}-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$(dirname "$PLAN_FILE")"

  set +e
  terraform plan \
    -var-file="$TFVARS_FILE" \
    "${extra_vars[@]}" \
    -out="$PLAN_FILE" \
    -detailed-exitcode
  local PLAN_EXIT=$?
  set -e

  if [[ $PLAN_EXIT -eq 0 ]]; then
    success "No changes detected for phase '${phase_label}'."
    return 0
  elif [[ $PLAN_EXIT -eq 1 ]]; then
    error "Terraform plan failed (phase: ${phase_label})."
  fi
  success "Plan complete for phase '${phase_label}' — changes detected."

  if [[ -z "$AUTO_APPROVE" ]]; then
    echo ""
    echo -e "${YELLOW}Review plan for phase '${phase_label}' above.${NC}"
    read -rp "Type 'yes' to apply: " CONFIRM
    [[ "$CONFIRM" == "yes" ]] || { info "Phase '${phase_label}' cancelled."; exit 0; }
  fi

  info "Applying plan (phase: ${phase_label})..."
  local START_TIME END_TIME DURATION MINUTES SECONDS
  START_TIME=$(date +%s)

  local APPLY_LOG
  APPLY_LOG="$(mktemp -t tf-apply.XXXXXX)"

  set +e
  terraform apply -auto-approve "$PLAN_FILE" 2>&1 | tee "$APPLY_LOG"
  local APPLY_EXIT=${PIPESTATUS[0]}
  set -e

  # Auto-import on "already exists" errors
  if [[ $APPLY_EXIT -ne 0 ]] && grep -q "already exists" "$APPLY_LOG"; then
    warn "Apply failed with 'already exists' errors. Attempting auto-import..."
    local RUN_IMPORT="yes"
    if [[ -z "$AUTO_APPROVE" ]]; then
      read -rp "Auto-import existing resources and retry apply? (Y/n): " ANS
      [[ "$ANS" =~ ^[Nn]$ ]] && RUN_IMPORT="no"
    fi
    if [[ "$RUN_IMPORT" == "yes" ]] && [[ -x "${SCRIPT_DIR}/import-existing.sh" ]]; then
      if "${SCRIPT_DIR}/import-existing.sh" "$ENVIRONMENT"; then
        APPLY_EXIT=0
      fi
    fi
  fi

  rm -f "$APPLY_LOG"

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))

  if [[ $APPLY_EXIT -eq 0 ]]; then
    success "Phase '${phase_label}' applied successfully (${MINUTES}m ${SECONDS}s)."
  else
    error "Phase '${phase_label}' failed (exit ${APPLY_EXIT})."
  fi
}

# --- Execute phases ---
if [[ -n "$LOGIC_APP_CODE_ONLY" ]]; then
  info "Logic App code-only mode: re-publishing workflow code without full apply."
  terraform apply \
    -var-file="$TFVARS_FILE" \
    -target=module.logic_app.null_resource.publish_workflows[0] \
    ${AUTO_APPROVE:+-auto-approve}
  success "Workflow code re-published."
  exit 0
fi

if [[ -n "$PHASED" ]]; then
  plan_and_apply "core"    1
  # If the user didn't request any add-ons, phase 2 is a no-op that will be
  # skipped by "No changes detected".
  plan_and_apply "add-ons" 2
else
  plan_and_apply "single" 0
fi

# --- Summary ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 ✅  Deployment Successful!                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
info "Deployment outputs:"
terraform output 2>/dev/null || true
echo ""
info "Next steps:"
echo "  1. Validate deployment: ./scripts/validate.sh ${ENVIRONMENT}"
echo "  2. Run validation notebooks in /validation/"
[[ -n "$WITH_ENTRA" ]] && echo "  3. Entra app secret available in Key Vault as ENTRA-APP-CLIENT-SECRET"
