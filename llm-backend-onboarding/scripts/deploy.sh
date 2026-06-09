#!/usr/bin/env bash
# =============================================================================
# LLM Backend Onboarding — Deploy Script
#
# Deploys LLM backends, backend pools, and policy fragments to an existing
# APIM instance using Terraform.
#
# Usage:
#   ./scripts/deploy.sh [OPTIONS]
#
# Options:
#   --auto-approve    Skip interactive confirmation
#   --plan-only       Show plan without applying
#   --destroy         Tear down all onboarded backends
#   --var-file FILE   Path to .tfvars file (default: terraform.tfvars)
#   -h, --help        Show this help message
#
# Examples:
#   ./scripts/deploy.sh                          # Plan + apply with confirmation
#   ./scripts/deploy.sh --auto-approve           # Apply without confirmation
#   ./scripts/deploy.sh --plan-only              # Show plan only
#   ./scripts/deploy.sh --var-file my-env.tfvars # Use a custom var file
#   ./scripts/deploy.sh --destroy                # Remove all backends
# =============================================================================

set -euo pipefail

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Parse arguments ---
AUTO_APPROVE=""
PLAN_ONLY=""
DESTROY=""
VAR_FILE="terraform.tfvars"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve) AUTO_APPROVE="-auto-approve" ;;
    --plan-only)    PLAN_ONLY="1" ;;
    --destroy)      DESTROY="1" ;;
    --var-file)     shift; VAR_FILE="$1" ;;
    -h|--help)      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              error "Unknown argument: $1 (use --help)" ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# --- Validate prerequisites ---
command -v terraform >/dev/null 2>&1 || error "terraform CLI not found. Install from https://developer.hashicorp.com/terraform/install"
command -v az >/dev/null 2>&1 || error "Azure CLI not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli"

# --- Check tfvars file ---
if [[ ! -f "$VAR_FILE" ]]; then
  error "Variables file '$VAR_FILE' not found.\n  Copy terraform.tfvars.example to terraform.tfvars and update with your values."
fi

# --- Check Azure authentication ---
info "Verifying Azure CLI authentication..."
if ! az account show &>/dev/null; then
  error "Not logged in to Azure CLI. Run 'az login' first."
fi

SUBSCRIPTION=$(az account show --query id -o tsv)
ACCOUNT_NAME=$(az account show --query name -o tsv)
info "Using subscription: $ACCOUNT_NAME ($SUBSCRIPTION)"

# --- Terraform init ---
info "Initializing Terraform..."
terraform init -upgrade

# --- Import existing resources (handles re-onboarding after main deploy) ---
info "Checking for existing resources to import into state..."
bash "$SCRIPT_DIR/import-existing.sh" --var-file "$VAR_FILE"

# --- Terraform action ---
if [[ -n "$DESTROY" ]]; then
  warn "DESTROYING all onboarded LLM backends..."
  terraform destroy -var-file="$VAR_FILE" $AUTO_APPROVE
  success "Destroy complete."
elif [[ -n "$PLAN_ONLY" ]]; then
  info "Running plan..."
  terraform plan -var-file="$VAR_FILE" -out=tfplan
  success "Plan saved to 'tfplan'. Review above and run './scripts/deploy.sh' to apply."
else
  info "Planning deployment..."
  terraform plan -var-file="$VAR_FILE" -out=tfplan

  echo ""
  if [[ -n "$AUTO_APPROVE" ]]; then
    info "Applying (auto-approved)..."
    terraform apply $AUTO_APPROVE tfplan
  else
    echo -e "${YELLOW}Review the plan above. Continue?${NC}"
    read -rp "  Apply changes? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      terraform apply tfplan
    else
      info "Cancelled."
      exit 0
    fi
  fi

  echo ""
  success "LLM Backend Onboarding complete!"
  echo ""
  info "Deployed resources:"
  terraform output -json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"  APIM:           {data.get('apim_name', {}).get('value', 'N/A')}\")
print(f\"  Gateway URL:    {data.get('apim_gateway_url', {}).get('value', 'N/A')}\")
backends = data.get('backend_ids', {}).get('value', [])
print(f\"  Backends ({len(backends)}):  {', '.join(backends)}\")
pools = data.get('pool_names', {}).get('value', [])
if pools:
    print(f\"  Pools ({len(pools)}):     {', '.join(pools)}\")
models = data.get('supported_models', {}).get('value', [])
print(f\"  Models ({len(models)}):    {', '.join(models)}\")
" 2>/dev/null || true
fi
