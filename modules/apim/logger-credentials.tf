# =============================================================================
# Logger credentials in Key Vault (logger_credentials_in_key_vault).
#
# APIM moves every credential a logger is given (the App Insights connection
# string, the managed identity client ID of the Event Hub loggers) into a
# secret named value it generates ("Logger-Credentials--<id>"): a secret stored
# in APIM, which the policy "API Management secret named values should be
# stored in Azure Key Vault" flags. A logger whose credentials are
# {{named value}} references gets no generated value, so the values go to Key
# Vault and APIM reads them through Key Vault-backed named values (APIM
# identity, Key Vault Secrets User).
#
# The secrets are written through ARM (Microsoft.KeyVault/vaults/secrets PUT),
# not the vault data plane: the vault is private by default, so a data-plane
# write from the deployer would hit the vault firewall. The PUT is idempotent,
# so it also works on a vault recovered from soft delete with the secrets
# still in it.
#
# Generated values left over from before the switch aren't removed by APIM:
# see DEPLOYMENT_GUIDE.md (APIM logger credentials in Key Vault) for the
# one-off cleanup command.
# =============================================================================

locals {
  logger_credentials_in_key_vault = var.logger_credentials_in_key_vault
  # The variable is sensitive; whether it's set isn't.
  logger_uses_connection_string = nonsensitive(var.app_insights_connection_string != "")

  # Named value (= Key Vault secret "apim-<name>") => value.
  logger_credential_names = local.logger_credentials_in_key_vault ? ["logger-identity-client-id", "logger-appinsights-connection-string"] : []
  logger_credential_values = {
    "logger-identity-client-id"            = var.managed_identity_client_id
    "logger-appinsights-connection-string" = var.app_insights_connection_string
  }

  logger_identity_client_id_ref = local.logger_credentials_in_key_vault ? "{{logger-identity-client-id}}" : var.managed_identity_client_id
  logger_connection_string_ref  = local.logger_credentials_in_key_vault ? "{{logger-appinsights-connection-string}}" : var.app_insights_connection_string

  secrets_key_vault_id  = try(var.secrets_key_vault.id, "")
  secrets_key_vault_uri = trimsuffix(try(var.secrets_key_vault.uri, ""), "/")

  # A classic SKU with apim_network_type = None has no VNet path to the vault's
  # private endpoint, and a user-assigned identity isn't a trusted service.
  apim_reaches_key_vault = local.is_vnet_injection || local.is_vnet_integration || try(var.secrets_key_vault.public_access_open, false)
}

# Expiry clock: ALZ guardrails (Enforce-GR-KeyVault) require secrets to expire.
# Key Vault's expiry is informational for APIM (references keep resolving after
# it); each rotation pushes it forward with a new version of the same value.
resource "time_rotating" "logger_credentials" {
  count         = local.logger_credentials_in_key_vault ? 1 : 0
  rotation_days = 60
}

resource "azapi_resource_action" "logger_credential_secret" {
  for_each = toset(local.logger_credential_names)

  type        = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  resource_id = "${local.secrets_key_vault_id}/secrets/apim-${each.key}"
  method      = "PUT"

  body = {
    properties = {
      value       = local.logger_credential_values[each.key]
      contentType = "apim-logger-credential"
      attributes = {
        enabled = true
        exp     = time_rotating.logger_credentials[0].unix + 90 * 24 * 3600
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.secrets_key_vault_id != "" && local.secrets_key_vault_uri != ""
      error_message = "logger_credentials_in_key_vault needs secrets_key_vault (id, uri)."
    }
    precondition {
      condition     = local.logger_uses_connection_string
      error_message = "logger_credentials_in_key_vault needs app_insights_connection_string: an instrumentation key alone isn't supported as a Key Vault reference."
    }
    precondition {
      condition     = try(var.secrets_key_vault.rbac_enabled, false)
      error_message = "logger_credentials_in_key_vault needs a Key Vault with RBAC authorization (the APIM identity is granted Key Vault Secrets User, not an access policy)."
    }
    precondition {
      condition     = local.apim_reaches_key_vault
      error_message = "logger_credentials_in_key_vault needs APIM to reach the Key Vault: use a V2 SKU or apim_network_type External/Internal, or open the vault (kv_public_network_access_enabled = true, network_acl_default_action = \"Allow\")."
    }
  }
}

resource "azurerm_api_management_named_value" "logger_credential" {
  for_each = toset(local.logger_credential_names)

  name                = each.key
  display_name        = each.key
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  secret              = true

  # Versionless: APIM picks up new versions on its own (every 4 hours).
  value_from_key_vault {
    secret_id          = "${local.secrets_key_vault_uri}/secrets/apim-${each.key}"
    identity_client_id = var.managed_identity_client_id
  }

  depends_on = [azapi_resource_action.logger_credential_secret]
}
