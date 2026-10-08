# =============================================================================
# Adopt APIM objects that already exist (WP-1.5, replaces scripts/import-existing.*)
# =============================================================================
# Re-running a contract after a state loss (or adopting one created by hand or
# by the Bicep accelerator) must not fail with "already exists". Each import
# block adopts the product, product policy, subscription or product-API link
# only when it exists under the APIM service (listed at plan time); missing
# objects are created, and objects already in state are left alone.
# =============================================================================

locals {
  apim_id = "/subscriptions/${var.apim.subscription_id}/resourceGroups/${var.apim.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim.name}"

  product_ids = { for s in var.services : s.code => "${s.code}-${local.product_postfix}" }

  existing_products      = toset(try(data.azapi_resource_list.products.output.names, []))
  existing_subscriptions = toset(try(data.azapi_resource_list.subscriptions.output.names, []))
  # Only products that exist can be listed for policies and API links.
  existing_service_products = { for code, id in local.product_ids : code => id if contains(local.existing_products, id) }
}

data "azapi_resource_list" "products" {
  type                   = "Microsoft.ApiManagement/service/products@2024-05-01"
  parent_id              = local.apim_id
  response_export_values = { names = "value[].name" }
}

data "azapi_resource_list" "subscriptions" {
  type                   = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  parent_id              = local.apim_id
  response_export_values = { names = "value[].name" }
}

data "azapi_resource_list" "product_policies" {
  for_each               = local.existing_service_products
  type                   = "Microsoft.ApiManagement/service/products/policies@2024-05-01"
  parent_id              = "${local.apim_id}/products/${each.value}"
  response_export_values = { names = "value[].name" }
}

data "azapi_resource_list" "product_apis" {
  for_each               = local.existing_service_products
  type                   = "Microsoft.ApiManagement/service/products/apis@2024-05-01"
  parent_id              = "${local.apim_id}/products/${each.value}"
  response_export_values = { names = "value[].name" }
}

import {
  for_each = local.existing_service_products
  to       = azurerm_api_management_product.service[each.key]
  id       = "${local.apim_id}/products/${each.value}"
}

import {
  for_each = { for code, id in local.existing_service_products : code => id if length(try(data.azapi_resource_list.product_policies[code].output.names, [])) > 0 }
  to       = azurerm_api_management_product_policy.service[each.key]
  id       = "${local.apim_id}/products/${each.value}"
}

import {
  for_each = { for code, id in local.product_ids : code => "${id}-SUB-01" if contains(local.existing_subscriptions, "${id}-SUB-01") }
  to       = azurerm_api_management_subscription.service[each.key]
  id       = "${local.apim_id}/subscriptions/${each.value}"
}

import {
  for_each = merge([
    for code, id in local.existing_service_products : {
      for api in lookup(var.api_name_mapping, code, []) : "${code}-${api}" => { product_id = id, api_name = api }
      if contains(try(data.azapi_resource_list.product_apis[code].output.names, []), api)
    }
  ]...)
  to = azurerm_api_management_product_api.service[each.key]
  id = "${local.apim_id}/products/${each.value.product_id}/apis/${each.value.api_name}"
}
