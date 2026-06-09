#!/usr/bin/env bash
# =============================================================================
# AI Citadel Governance Hub — Destroy Script
# Usage: ./scripts/destroy.sh [dev|prod] [--auto-approve]
# WARNING: This permanently deletes all Citadel resources for the environment.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENVIRONMENT="${1:-dev}"
AUTO_APPROVE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="${ROOT_DIR}/environments/${ENVIRONMENT}.tfvars"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       🏰  AI Citadel Governance Hub — Terraform Destroy      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${RED}⚠  WARNING: This will PERMANENTLY DELETE all Citadel resources!${NC}"
echo -e "${RED}⚠  Environment: ${ENVIRONMENT}${NC}"
echo ""

command -v terraform >/dev/null 2>&1 || error "terraform not found."
[[ -f "$TFVARS_FILE" ]] || error "Vars file not found: ${TFVARS_FILE}"

cd "$ROOT_DIR"
terraform init -upgrade >/dev/null 2>&1

if [[ "$AUTO_APPROVE" != "--auto-approve" ]]; then
  read -rp "Type the environment name '${ENVIRONMENT}' to confirm destruction: " CONFIRM
  [[ "$CONFIRM" == "$ENVIRONMENT" ]] || { info "Destruction cancelled."; exit 0; }
fi

info "Running terraform destroy..."
terraform destroy \
  -var-file="$TFVARS_FILE" \
  -auto-approve \
  2>&1 | while IFS= read -r line; do echo "  $line"; done

success "All resources for environment '${ENVIRONMENT}' have been destroyed."
