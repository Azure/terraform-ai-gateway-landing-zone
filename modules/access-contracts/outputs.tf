output "products" {
  description = "Map of service code → product metadata."
  value = {
    for k, p in azurerm_api_management_product.service :
    k => { product_id = p.product_id, display_name = p.display_name }
  }
}

output "subscriptions" {
  description = "Map of service code → subscription metadata."
  value = {
    for k, s in azurerm_api_management_subscription.service :
    k => { display_name = s.display_name, product_id = s.product_id }
  }
  sensitive = true
}

output "endpoints" {
  description = "Per-service endpoint + key (only populated when Key Vault is not used)."
  value = var.use_target_key_vault ? {} : {
    for k, s in var.services :
    s.code => {
      endpoint = "${var.apim_gateway_url}/${lookup(var.api_name_mapping, s.code, [""])[0]}"
      api_key  = azurerm_api_management_subscription.service[s.code].primary_key
    }
  }
  sensitive = true
}

output "foundry_connections" {
  description = "Map of Foundry APIM connections created (by service code)."
  value = var.use_target_foundry ? {
    for k, c in azapi_resource.foundry_connection :
    k => { name = c.name, id = c.id }
  } : {}
}
