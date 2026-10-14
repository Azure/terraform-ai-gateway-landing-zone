# =============================================================================
# Logger credentials in Key Vault (credentials_in_key_vault).
#
# APIM moves every credential a logger is given (the App Insights connection string, the
# identity client ID of the Event Hub and App Insights loggers) into a secret named value it
# generates ("Logger-Credentials--<id>"): a secret stored in APIM, which the policy
# "API Management secret named values should be stored in Azure Key Vault" flags. A logger
# whose credentials are {{named value}} references gets no generated value, so the values go
# to Key Vault and APIM reads them through Key Vault-backed named values (APIM identity, Key
# Vault Secrets User).
#
# Generated values left over from before the switch aren't removed by APIM: see the
# Deployment Guide (logger credentials) for the cleanup command.
# =============================================================================

locals {
  credentials_in_key_vault = var.credentials_in_key_vault
  # The variable is sensitive; whether it's set isn't.
  uses_connection_string = nonsensitive(var.app_insights_connection_string != "")

  # Named value (= Key Vault secret "apim-<name>") => value. Both always: credentials in Key Vault
  # require the connection string (precondition on the App Insights logger).
  logger_credential_names = local.credentials_in_key_vault ? ["logger-identity-client-id", "logger-appinsights-connection-string"] : []
  logger_credential_values = {
    "logger-identity-client-id"            = var.managed_identity_client_id
    "logger-appinsights-connection-string" = var.app_insights_connection_string
  }

  identity_client_id_ref = local.credentials_in_key_vault ? "{{logger-identity-client-id}}" : var.managed_identity_client_id
  connection_string_ref  = local.credentials_in_key_vault && local.uses_connection_string ? "{{logger-appinsights-connection-string}}" : var.app_insights_connection_string
}

# Expiry clock: ALZ Enforce-GR-KeyVault requires an expiry. Key Vault's expiry is informational
# (reads keep working after it); each rotation pushes it forward in place (no new version).
resource "time_rotating" "logger_credentials" {
  count         = local.credentials_in_key_vault ? 1 : 0
  rotation_days = 60
}

resource "azurerm_key_vault_secret" "logger_credential" {
  for_each = toset(local.logger_credential_names)

  key_vault_id    = var.credentials_key_vault_id
  name            = "apim-${each.key}"
  value           = local.logger_credential_values[each.key]
  content_type    = "apim-logger-credential"
  expiration_date = timeadd(time_rotating.logger_credentials[0].rfc3339, "${90 * 24}h")
}

resource "azurerm_api_management_named_value" "logger_credential" {
  for_each = toset(local.logger_credential_names)

  name                = each.key
  display_name        = each.key
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  secret              = true

  value_from_key_vault {
    secret_id          = azurerm_key_vault_secret.logger_credential[each.key].versionless_id
    identity_client_id = var.managed_identity_client_id
  }
}
