# =============================================================================
# APIM ADDITIONAL NAMED VALUES + OPERATION POLICIES — Bicep parity (apim.bicep)
# =============================================================================

# -----------------------------------------------------------------------------
# JWT-* named values (Bicep parity: always created; values are placeholders
# when enable_jwt_auth = false so deployment always succeeds)
# -----------------------------------------------------------------------------

locals {
  jwt_tenant_value        = var.enable_jwt_auth && var.jwt_tenant_id != "" ? var.jwt_tenant_id : "not-configured"
  jwt_app_reg_value       = var.enable_jwt_auth && var.jwt_app_registration_id != "" ? var.jwt_app_registration_id : "not-configured"
  jwt_issuer_value        = var.enable_jwt_auth ? "${var.azure_login_endpoint}${local.jwt_tenant_value}/v2.0" : "not-configured"
  jwt_openid_config_value = var.enable_jwt_auth ? "${var.azure_login_endpoint}${local.jwt_tenant_value}/v2.0/.well-known/openid-configuration" : "not-configured"
}

resource "azurerm_api_management_named_value" "jwt_tenant_id" {
  name                = "JWT-TenantId"
  display_name        = "JWT-TenantId"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = local.jwt_tenant_value
  secret              = false
}

resource "azurerm_api_management_named_value" "jwt_app_registration_id" {
  name                = "JWT-AppRegistrationId"
  display_name        = "JWT-AppRegistrationId"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = local.jwt_app_reg_value
  secret              = false
}

resource "azurerm_api_management_named_value" "jwt_issuer" {
  name                = "JWT-Issuer"
  display_name        = "JWT-Issuer"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = local.jwt_issuer_value
  secret              = false
}

resource "azurerm_api_management_named_value" "jwt_openid_config_url" {
  name                = "JWT-OpenIdConfigUrl"
  display_name        = "JWT-OpenIdConfigUrl"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = local.jwt_openid_config_value
  secret              = false
}

resource "azurerm_api_management_named_value" "pii_service_key" {
  count               = var.enable_pii_redaction ? 1 : 0
  name                = "piiServiceKey"
  display_name        = "piiServiceKey"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.pii_service_key
  secret              = true
}

resource "azurerm_api_management_named_value" "aws_access_key" {
  name                = "aws-access-key"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  display_name        = "aws-access-key"
  value               = var.aws_access_key != "" ? var.aws_access_key : "NOT_CONFIGURED"
  secret              = true
}

resource "azurerm_api_management_named_value" "aws_secret_key" {
  name                = "aws-secret-key"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  display_name        = "aws-secret-key"
  value               = var.aws_secret_key != "" ? var.aws_secret_key : "NOT_CONFIGURED"
  secret              = true
}

resource "azurerm_api_management_named_value" "aws_region" {
  name                = "aws-region"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  display_name        = "aws-region"
  value               = var.aws_region != "" ? var.aws_region : "NOT_CONFIGURED"
  secret              = false
}
