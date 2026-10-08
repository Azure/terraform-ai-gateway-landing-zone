# Named values the shared fragments reference. APIM validates references when
# a fragment or policy is saved, so these come first.
#
# With Entra auth off the values fall back to placeholders that still resolve
# (APIM checks <openid-config url> at save time); the entra-auth flag gates
# validation at runtime. llm-backend-onboarding reads entra-auth to decide
# whether its APIs require a subscription key.

locals {
  entra_on = var.entra_auth.enabled

  jwt_tenant = local.entra_on ? local.entra.tenant_id : "not-configured"

  plain_named_values = merge(
    {
      "uami-client-id"        = data.azurerm_user_assigned_identity.apim.client_id
      "tenant-id"             = local.entra_on ? local.entra.tenant_id : "common"
      "client-id"             = local.entra_on && local.entra.client_id != "" ? local.entra.client_id : "00000000-0000-0000-0000-000000000000"
      "audience"              = local.entra_on && local.entra.audience != "" ? local.entra.audience : "api://disabled"
      "entra-auth"            = tostring(local.entra_on)
      "JWT-TenantId"          = local.jwt_tenant
      "JWT-AppRegistrationId" = local.entra_on && local.entra.client_id != "" ? local.entra.client_id : "not-configured"
      "JWT-Issuer"            = local.entra_on ? "${var.entra_auth.login_endpoint}${local.jwt_tenant}/v2.0" : "not-configured"
      "JWT-OpenIdConfigUrl"   = local.entra_on ? "${var.entra_auth.login_endpoint}${local.jwt_tenant}/v2.0/.well-known/openid-configuration" : "not-configured"
    },
    var.features.pii_redaction ? { piiServiceUrl = local.foundry_endpoint } : {},
    var.features.content_safety ? { contentSafetyServiceUrl = local.foundry_endpoint } : {},
  )
}

resource "azurerm_api_management_named_value" "plain" {
  for_each = local.plain_named_values

  name                = each.key
  display_name        = each.key
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name
  value               = each.value
  secret              = false
}

check "entra_app_found" {
  assert {
    condition     = !var.entra_auth.enabled || local.entra.client_id != ""
    error_message = "entra_auth.enabled: the gateway app wasn't found. Apply stacks/identity first, or set entra_auth.client_id / audience explicitly."
  }
}
