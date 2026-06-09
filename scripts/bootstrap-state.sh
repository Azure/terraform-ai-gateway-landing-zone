#!/usr/bin/env bash
# =============================================================================
# AI Citadel Governance Hub — Bootstrap Terraform Remote State
# Run ONCE before first deploy to create the Azure Storage backend for state.
# Usage: ./scripts/bootstrap-state.sh [location]
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

LOCATION="${1:-eastus}"
RG_NAME="rg-terraform-state-citadel"
SA_NAME="stcitadelstate$(shuf -i 10000-99999 -n 1)"
CONTAINER_NAME="citadel-tfstate"

info "Creating Terraform remote state backend..."
info "  Resource Group   : ${RG_NAME}"
info "  Storage Account  : ${SA_NAME}"
info "  Container        : ${CONTAINER_NAME}"
info "  Location         : ${LOCATION}"
echo ""

# Create resource group
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION" \
  --tags "Purpose=TerraformState" "ManagedBy=Bootstrap" \
  --output none

success "Resource group created: ${RG_NAME}"

# Create storage account
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --output none

success "Storage account created: ${SA_NAME}"

# Create container
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$SA_NAME" \
  --auth-mode login \
  --output none

success "Container created: ${CONTAINER_NAME}"

# Enable versioning (for state file history)
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --output none

success "Blob versioning enabled."

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅  Remote state backend is ready!"
echo ""
echo "  Uncomment and update the backend block in versions.tf:"
echo ""
echo '  backend "azurerm" {'
echo "    resource_group_name  = \"${RG_NAME}\""
echo "    storage_account_name = \"${SA_NAME}\""
echo "    container_name       = \"${CONTAINER_NAME}\""
echo '    key                  = "citadel.terraform.tfstate"'
echo '  }'
echo "════════════════════════════════════════════════════════"
