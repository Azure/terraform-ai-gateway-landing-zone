# =============================================================================
# APIM — Foundry connection subscription
#
# Creates a dedicated named subscription whose primary key is exported and then
# consumed by the foundry module to authenticate Foundry → APIM connections.
# This avoids using the APIM master subscription key directly.
# =============================================================================

resource "azurerm_api_management_subscription" "foundry_connection" {
  count               = var.enable_foundry_apim_connection ? 1 : 0
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  display_name        = "foundry-apim-connection"
  state               = "active"
  allow_tracing       = false
}
