# =============================================================================
# Citadel Access Contracts — Outputs
# =============================================================================

output "apim_gateway_url" {
  description = "Base URL of the APIM gateway."
  value       = local.gateway_url
}

output "use_key_vault" {
  description = "Whether endpoint/key secrets were written to Key Vault."
  value       = var.use_target_key_vault
}

output "products" {
  description = "Map of service code → product metadata."
  value = {
    for k, p in azurerm_api_management_product.service :
    k => {
      product_id   = p.product_id
      display_name = p.display_name
    }
  }
}

output "subscriptions" {
  description = "Per-service subscription metadata. When Key Vault is used, only the secret references are returned."
  value = {
    for s in var.services :
    s.code => {
      name                           = "${s.code}-${local.product_postfix}-SUB-01"
      product_id                     = "${s.code}-${local.product_postfix}"
      key_vault_endpoint_secret_name = var.use_target_key_vault ? lower(replace(s.endpoint_secret_name, "_", "-")) : ""
      key_vault_api_key_secret_name  = var.use_target_key_vault ? lower(replace(s.api_key_secret_name, "_", "-")) : ""
    }
  }
}

# When NOT using Key Vault, expose the actual endpoints + keys. These are
# sensitive — store them securely (environment variables, CI/CD secrets, etc.).
output "endpoints" {
  description = "Per-service endpoint + API key. Only populated when use_target_key_vault = false."
  sensitive   = true
  value = var.use_target_key_vault ? {} : {
    for s in var.services :
    s.code => {
      product_id        = "${s.code}-${local.product_postfix}"
      subscription_name = "${s.code}-${local.product_postfix}-SUB-01"
      endpoint          = local.service_endpoint_url[s.code]
      api_key           = azurerm_api_management_subscription.service[s.code].primary_key
    }
  }
}

output "use_foundry" {
  description = "Whether Foundry connections were created."
  value       = var.use_target_foundry
}

output "foundry_connections" {
  description = "Map of service code → created Foundry connection metadata."
  value = var.use_target_foundry ? {
    for k, c in azapi_resource.foundry_connection :
    k => {
      connection_name = c.name
      connection_id   = c.id
      target_url      = local.service_endpoint_url[k]
      foundry_account = var.foundry.account_name
      foundry_project = var.foundry.project_name
    }
  } : {}
}
