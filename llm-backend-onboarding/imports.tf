# =============================================================================
# Adopt APIM objects that already exist (WP-1.5, replaces scripts/import-existing.*)
# =============================================================================
# The main deployment creates the LLM backends, pools, routing fragments and
# named values this configuration manages. Each import block below adopts the
# object only when it exists under the APIM service (listed at plan time);
# objects that are missing are simply created, and objects already in state
# are left alone (an import of a managed address is a no-op).
# =============================================================================

locals {
  apim_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"

  existing_backends       = toset(try(data.azapi_resource_list.backends.output.names, []))
  existing_fragments      = toset(try(data.azapi_resource_list.policy_fragments.output.names, []))
  existing_named_values   = toset(try(data.azapi_resource_list.named_values.output.names, []))
  singleton_fragments     = { set_backend_pools = "set-backend-pools", get_available_models = "get-available-models", metadata_config = "metadata-config", resolve_model_alias = "resolve-model-alias" }
  singleton_named_values  = { aws_access_key = "aws-access-key", aws_secret_key = "aws-secret-key", aws_region = "aws-region" }
  importable_backend_keys = [for b in var.llm_backend_config : b.backend_id if contains(local.existing_backends, b.backend_id)]
}

data "azapi_resource_list" "backends" {
  type                   = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  parent_id              = local.apim_id
  response_export_values = { names = "value[].name" }
}

data "azapi_resource_list" "policy_fragments" {
  type                   = "Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview"
  parent_id              = local.apim_id
  response_export_values = { names = "value[].name" }
}

data "azapi_resource_list" "named_values" {
  type                   = "Microsoft.ApiManagement/service/namedValues@2024-06-01-preview"
  parent_id              = local.apim_id
  response_export_values = { names = "value[].name" }
}

import {
  for_each = toset(local.importable_backend_keys)
  to       = azapi_resource.llm_backend[each.key]
  id       = "${local.apim_id}/backends/${each.key}"
}

import {
  for_each = { for k in keys(local.pool_configs) : k => k if contains(local.existing_backends, k) }
  to       = azapi_resource.llm_backend_pool[each.key]
  id       = "${local.apim_id}/backends/${each.key}"
}

import {
  for_each = { for k in keys(local.static_fragments) : k => k if contains(local.existing_fragments, k) }
  to       = azurerm_api_management_policy_fragment.static[each.key]
  id       = "${local.apim_id}/policyFragments/${each.key}"
}

import {
  for_each = contains(local.existing_fragments, local.singleton_fragments.set_backend_pools) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_policy_fragment.set_backend_pools
  id       = "${local.apim_id}/policyFragments/${local.singleton_fragments.set_backend_pools}"
}

import {
  for_each = contains(local.existing_fragments, local.singleton_fragments.get_available_models) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_policy_fragment.get_available_models
  id       = "${local.apim_id}/policyFragments/${local.singleton_fragments.get_available_models}"
}

import {
  for_each = contains(local.existing_fragments, local.singleton_fragments.metadata_config) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_policy_fragment.metadata_config
  id       = "${local.apim_id}/policyFragments/${local.singleton_fragments.metadata_config}"
}

import {
  for_each = contains(local.existing_fragments, local.singleton_fragments.resolve_model_alias) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_policy_fragment.resolve_model_alias
  id       = "${local.apim_id}/policyFragments/${local.singleton_fragments.resolve_model_alias}"
}

import {
  for_each = contains(local.existing_named_values, local.singleton_named_values.aws_access_key) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_named_value.aws_access_key
  id       = "${local.apim_id}/namedValues/${local.singleton_named_values.aws_access_key}"
}

import {
  for_each = contains(local.existing_named_values, local.singleton_named_values.aws_secret_key) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_named_value.aws_secret_key
  id       = "${local.apim_id}/namedValues/${local.singleton_named_values.aws_secret_key}"
}

import {
  for_each = contains(local.existing_named_values, local.singleton_named_values.aws_region) ? toset(["x"]) : toset([])
  to       = azurerm_api_management_named_value.aws_region
  id       = "${local.apim_id}/namedValues/${local.singleton_named_values.aws_region}"
}

import {
  for_each = { for k in keys(local.backend_auth_named_values) : k => k if contains(local.existing_named_values, k) }
  to       = azurerm_api_management_named_value.backend_api_key[each.key]
  id       = "${local.apim_id}/namedValues/${each.key}"
}
