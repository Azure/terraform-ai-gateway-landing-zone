# Credentials for non-Foundry backends: Key Vault references (versionless secret
# URIs), resolved by the APIM identity. The aws-* values always exist so the
# set-backend-authorization fragment compiles without Bedrock backends.

locals {
  aws_named_values = {
    "aws-access-key" = var.aws.access_key_secret_uri
    "aws-secret-key" = var.aws.secret_key_secret_uri
  }

  backend_auth_named_values = {
    for b in local.llm_backend_config :
    b.auth_config.named_value_key => {
      key_vault_secret_uri = try(b.auth_config.key_vault_secret_uri, null) != null ? b.auth_config.key_vault_secret_uri : ""
      secret_value         = try(b.auth_config.secret_value, null) != null ? b.auth_config.secret_value : ""
    }
    if try(b.auth_config.named_value_key, null) != null && try(b.auth_config.named_value_key, "") != ""
  }
}

resource "azurerm_api_management_named_value" "aws" {
  for_each = local.aws_named_values

  name                = each.key
  display_name        = each.key
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name
  secret              = each.value != ""
  value               = each.value == "" ? "NOT_CONFIGURED" : null

  dynamic "value_from_key_vault" {
    for_each = each.value != "" ? [1] : []
    content {
      secret_id          = each.value
      identity_client_id = data.azurerm_user_assigned_identity.apim.client_id
    }
  }
}

resource "azurerm_api_management_named_value" "aws_region" {
  name                = "aws-region"
  display_name        = "aws-region"
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name
  value               = var.aws.region != "" ? var.aws.region : "NOT_CONFIGURED"
  secret              = false
}

resource "azurerm_api_management_named_value" "backend_api_key" {
  for_each = local.backend_auth_named_values

  name                = each.key
  display_name        = each.key
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name
  secret              = each.value.key_vault_secret_uri != "" || each.value.secret_value != ""
  value               = each.value.key_vault_secret_uri == "" ? (each.value.secret_value != "" ? each.value.secret_value : "NOT_CONFIGURED") : null

  dynamic "value_from_key_vault" {
    for_each = each.value.key_vault_secret_uri != "" ? [1] : []
    content {
      secret_id          = each.value.key_vault_secret_uri
      identity_client_id = data.azurerm_user_assigned_identity.apim.client_id
    }
  }
}

# A plain secret_value lands in state: tests only (review finding S1).
check "no_plaintext_backend_secrets" {
  assert {
    condition     = alltrue([for k, v in local.backend_auth_named_values : v.secret_value == "" || v.key_vault_secret_uri != ""])
    error_message = "auth_config.secret_value is set for: ${join(", ", [for k, v in local.backend_auth_named_values : k if v.secret_value != "" && v.key_vault_secret_uri == ""])}. The value is stored in state; use auth_config.key_vault_secret_uri instead."
  }
}
