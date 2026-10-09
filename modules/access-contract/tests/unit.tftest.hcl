# Unit tests (plan only, no Azure access):
#   terraform init -backend=false && terraform test
# azapi is NOT mocked (mock providers don't support the ephemeral key read);
# these runs never open it (no Key Vault, no Foundry), so the real provider
# plans without credentials.

mock_provider "azurerm" {
  override_during = plan
}
mock_provider "time" {
  override_during = plan
}

variables {
  api_management = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
    name                = "apim-aigw-dev"
    resource_group_name = "rg-aigw-dev"
    gateway_url         = "https://apim-aigw-dev.azure-api.net"
  }
  use_case         = { business_unit = "HR", use_case_name = "ChatAgent", environment = "DEV" }
  api_name_mapping = { LLM = ["universal-llm-api", "azure-openai-api"], DOC = ["document-intelligence-api"] }
  api_paths        = { LLM = "models", DOC = "documentintelligence" }
  services = [
    { code = "LLM", endpoint_secret_name = "HR_LLM_ENDPOINT", api_key_secret_name = "HR_LLM_KEY" },
    { code = "DOC", endpoint_secret_name = "HR_DOC_ENDPOINT", api_key_secret_name = "HR_DOC_KEY", policy_xml = "<policies><inbound><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>" },
  ]
}

run "products_apis_and_keyless_subscriptions" {
  command = plan

  assert {
    condition     = output.products == { LLM = "LLM-HR-ChatAgent-DEV", DOC = "DOC-HR-ChatAgent-DEV" }
    error_message = "Products are named <code>-<bu>-<usecase>-<env>."
  }
  assert {
    condition     = sort(keys(azurerm_api_management_product_api.service)) == tolist(["DOC-document-intelligence-api", "LLM-azure-openai-api", "LLM-universal-llm-api"])
    error_message = "Every mapped API is attached to its product."
  }
  assert {
    condition     = azapi_resource.subscription["LLM"].name == "LLM-HR-ChatAgent-DEV-SUB-01" && endswith(azapi_resource.subscription["LLM"].body.properties.scope, "/products/LLM-HR-ChatAgent-DEV")
    error_message = "One subscription per product, scoped to it (azapi: APIM never returns keys on GET)."
  }
  assert {
    condition     = azurerm_api_management_product_policy.service["DOC"].xml_content == var.services[1].policy_xml
    error_message = "A complete policy_xml replaces the generated policy."
  }
  assert {
    condition     = output.endpoints == { LLM = "https://apim-aigw-dev.azure-api.net/models", DOC = "https://apim-aigw-dev.azure-api.net/documentintelligence" }
    error_message = "Endpoints are the gateway URL plus the first API's path."
  }
  assert {
    condition     = length(azurerm_key_vault_secret.key) == 0 && length(azapi_resource.foundry_connection) == 0 && !local.needs_key
    error_message = "No Key Vault and no Foundry: the key is never read."
  }
}

run "secret_validity_must_exceed_rotation" {
  command = plan

  variables {
    secret_rotation_days = 90
    secret_validity_days = 60
  }

  expect_failures = [var.secret_validity_days]
}

run "foundry_defaults_to_project_managed_identity" {
  command = plan

  assert {
    condition     = output.foundry_connection_auth == { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" }
    error_message = "Foundry connections default to project managed identity with the cognitive services audience."
  }
}

run "foundry_api_key_mode_has_no_audience" {
  command = plan

  variables {
    foundry_config = { auth_type = "ApiKey" }
  }

  assert {
    condition     = output.foundry_connection_auth == { auth_type = "ApiKey", managed_identity_audience = "" }
    error_message = "ApiKey mode reports no token audience."
  }
}

run "foundry_custom_audience" {
  command = plan

  variables {
    foundry_config = { managed_identity_audience = "api://custom-gateway" }
  }

  assert {
    condition     = output.foundry_connection_auth.managed_identity_audience == "api://custom-gateway"
    error_message = "The audience can be overridden."
  }
}

run "foundry_rejects_unknown_auth_type" {
  command = plan

  variables {
    foundry_config = { auth_type = "Basic" }
  }

  expect_failures = [var.foundry_config]
}

run "foundry_rejects_empty_audience" {
  command = plan

  variables {
    foundry_config = { managed_identity_audience = "  " }
  }

  expect_failures = [var.foundry_config]
}

run "foundry_rejects_api_key_header_in_managed_identity_mode" {
  command = plan

  variables {
    foundry_config = { custom_headers = { "api-key" = "x" } }
  }

  expect_failures = [var.foundry_config]
}

# --- generated product policy --------------------------------------------------

run "default_policy_restricts_nothing" {
  command = plan

  assert {
    condition = (
      startswith(azurerm_api_management_product_policy.service["LLM"].xml_content, "<policies>") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "set-llm-requested-model") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "name=\"enableResponseHeaders\" value=\"@(true)\"") &&
      !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "allowedModels") &&
      !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "llm-token-limit") &&
      !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "jwtRequired")
    )
    error_message = "With no properties: every model, no token limit, no JWT, response headers on."
  }
  assert {
    condition     = !can(regex("\n[ \t]*\n", azurerm_api_management_product_policy.service["LLM"].xml_content))
    error_message = "The template's directive lines leave no blank lines."
  }
}

run "policy_from_properties" {
  command = plan

  variables {
    services = [{
      code                 = "LLM"
      endpoint_secret_name = "HR_LLM_ENDPOINT"
      api_key_secret_name  = "HR_LLM_KEY"
      allowed_models       = ["gpt-5.4-mini", "fast"]
      token_limit          = { tokens_per_minute = 2000, token_quota = 50000, token_quota_period = "Daily" }
    }]
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<set-variable name=\"allowedModels\" value=\"gpt-5.4-mini,fast\" />") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "validate-model-access") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<llm-token-limit counter-key=\"@(context.Subscription.Id)\" tokens-per-minute=\"2000\" token-quota=\"50000\" token-quota-period=\"Daily\" estimate-prompt-tokens=\"false\" />")
    )
    error_message = "Allowed models and the token limit come from the properties."
  }
}

run "token_limit_parts_are_optional" {
  command = plan

  variables {
    services = [
      { code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", token_limit = { tokens_per_minute = 500 } },
      { code = "DOC", endpoint_secret_name = "C", api_key_secret_name = "D", token_limit = { token_quota = 1000 } },
    ]
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "tokens-per-minute=\"500\" estimate-prompt-tokens") &&
      !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "token-quota")
    )
    error_message = "A per-minute limit alone sets no quota."
  }
  assert {
    condition     = strcontains(azurerm_api_management_product_policy.service["DOC"].xml_content, "token-quota=\"1000\" token-quota-period=\"Monthly\" estimate-prompt-tokens") && !strcontains(azurerm_api_management_product_policy.service["DOC"].xml_content, "tokens-per-minute")
    error_message = "A quota alone defaults to a monthly period."
  }
}

run "response_headers_can_be_switched_off" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", enable_response_headers = false }]
  }

  assert {
    condition     = !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "enableResponseHeaders")
    error_message = "enable_response_headers = false leaves the variable out."
  }
}

run "jwt_policy_uses_the_connection_audience_and_the_tenant" {
  command = plan

  variables {
    tenant_id      = "11111111-2222-3333-4444-555555555555"
    foundry_config = { managed_identity_audience = "api://custom-gateway" }
    services       = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", jwt_required = true }]
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<set-variable name=\"jwtRequired\" value=\"true\" />") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<set-variable name=\"jwtAudience\" value=\"api://custom-gateway\" />") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "value=\"https://sts.windows.net/11111111-2222-3333-4444-555555555555/\"") &&
      strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "value=\"https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0/.well-known/openid-configuration\"")
    )
    error_message = "jwt_required validates the audience the Foundry connection sends, for the tenant."
  }
}

run "jwt_audience_is_xml_escaped" {
  command = plan

  variables {
    tenant_id      = "11111111-2222-3333-4444-555555555555"
    foundry_config = { managed_identity_audience = "api://a&b\"<c" }
    services       = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", jwt_required = true }]
  }

  assert {
    condition     = strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "value=\"api://a&amp;b&quot;&lt;c\"")
    error_message = "The audience can't break out of the XML attribute."
  }
}

run "jwt_needs_a_tenant" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", jwt_required = true }]
  }

  expect_failures = [var.tenant_id]
}

run "jwt_with_a_custom_policy_needs_no_tenant" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", jwt_required = true, policy_xml = "<policies />" }]
  }

  assert {
    condition     = azurerm_api_management_product_policy.service["LLM"].xml_content == "<policies />"
    error_message = "policy_xml wins over the generated policy and the properties."
  }
}

run "model_names_cannot_inject_xml" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", allowed_models = ["gpt-4o\" /><x a=\""] }]
  }

  expect_failures = [var.services]
}

run "token_limit_needs_a_limit" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", token_limit = {} }]
  }

  expect_failures = [var.services]
}

run "token_limit_rejects_unknown_period" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", token_limit = { token_quota = 10, token_quota_period = "Yearish" } }]
  }

  expect_failures = [var.services]
}

run "token_limit_must_be_positive" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", token_limit = { tokens_per_minute = 0 } }]
  }

  expect_failures = [var.services]
}

# --- asset-type-aware (multi-asset) product policy --------------------------------

run "llm_only_service_is_not_classified" {
  command = plan

  assert {
    condition     = !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "set-asset-kind") && !strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<choose>")
    error_message = "Without tool or agent APIs the policy has no classification and no <choose>."
  }
}

# Golden file: the policy upstream's default-multi-product-policy.xml describes (same elements,
# same order, same attributes), with the granted tool and agent APIs listed.
run "multi_asset_policy_matches_the_upstream_default" {
  command = plan

  variables {
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp", "hr-agent"] }
    api_paths        = { MULTI = "models" }
    services = [{
      code                 = "MULTI"
      endpoint_secret_name = "A"
      api_key_secret_name  = "B"
      allowed_models       = ["gpt-4o", "gpt-4.1", "gpt-5.4-mini"]
      token_limit          = { tokens_per_minute = 1000, token_quota = 100000, token_quota_period = "Monthly" }
      tool_apis            = ["weather-mcp"]
      tool_limit           = { calls_per_minute = 60, call_quota = 10000 }
      agent_apis           = ["hr-agent"]
      agent_limit          = { calls_per_minute = 30, call_quota = 5000 }
    }]
  }

  assert {
    condition     = azurerm_api_management_product_policy.service["MULTI"].xml_content == file("${path.module}/tests/fixtures/multi-asset-policy.golden")
    error_message = "The generated multi-asset policy changed (tests/fixtures/multi-asset-policy.golden)."
  }
}

run "multi_asset_policy_classifies_then_branches" {
  command = plan

  variables {
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp", "ms-learn-mcp"] }
    api_paths        = { MULTI = "models" }
    services = [{
      code                 = "MULTI"
      endpoint_secret_name = "A"
      api_key_secret_name  = "B"
      allowed_models       = ["fast"]
      tool_apis            = ["weather-mcp", "ms-learn-mcp"]
      tool_limit           = { calls_per_minute = 60, call_quota = 5000, call_quota_period = "Daily" }
    }]
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<set-variable name=\"contractToolApis\" value=\"weather-mcp,ms-learn-mcp\" />") &&
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<set-variable name=\"contractAgentApis\" value=\"\" />") &&
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<include-fragment fragment-id=\"set-asset-kind\" />")
    )
    error_message = "The granted tool APIs are listed by name before the set-asset-kind fragment."
  }
  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<rate-limit-by-key calls=\"60\" renewal-period=\"60\"") &&
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<quota-by-key calls=\"5000\" renewal-period=\"86400\"") &&
      !strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "\"agent\")")
    )
    error_message = "Tool limits become a per-minute rate limit and a quota whose period is in seconds; no agent branch without agent limits."
  }
  assert {
    condition     = length(split("allowedModels", azurerm_api_management_product_policy.service["MULTI"].xml_content)[0]) > length(split("assetKind\",\"llm\"", azurerm_api_management_product_policy.service["MULTI"].xml_content)[0])
    error_message = "Model RBAC sits inside the LLM branch, so tool calls are never model-checked."
  }
}

run "tool_apis_without_limits_still_keep_llm_rules_off_tool_calls" {
  command = plan

  variables {
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp"] }
    api_paths        = { MULTI = "models" }
    services         = [{ code = "MULTI", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"] }]
  }

  assert {
    condition     = strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "set-asset-kind") && strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "== \"llm\")") && !strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "== \"tool\")")
    error_message = "Classification is needed even without tool limits, so the LLM rules run for LLM requests only."
  }
}

run "tool_and_agent_limit_parts_are_optional" {
  command = plan

  variables {
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp", "hr-agent"] }
    api_paths        = { MULTI = "models" }
    services = [{
      code                 = "MULTI"
      endpoint_secret_name = "A"
      api_key_secret_name  = "B"
      tool_apis            = ["weather-mcp"]
      tool_limit           = { calls_per_minute = 10 }
      agent_apis           = ["hr-agent"]
      agent_limit          = { call_quota = 100, call_quota_period = "Hourly" }
    }]
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<rate-limit-by-key calls=\"10\"") &&
      strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "<quota-by-key calls=\"100\" renewal-period=\"3600\" counter-key=\"@(context.Subscription.Id + \":agent\")\" />") &&
      !strcontains(azurerm_api_management_product_policy.service["MULTI"].xml_content, "\":tool\")\" />\n")
    )
    error_message = "A per-minute limit alone sets no quota; a quota alone sets no rate limit."
  }
}

run "multi_asset_jwt_is_checked_before_classification" {
  command = plan

  variables {
    tenant_id        = "11111111-2222-3333-4444-555555555555"
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp"] }
    api_paths        = { MULTI = "models" }
    services         = [{ code = "MULTI", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"], jwt_required = true }]
  }

  assert {
    condition     = length(split("jwtRequired", azurerm_api_management_product_policy.service["MULTI"].xml_content)[0]) < length(split("contractToolApis", azurerm_api_management_product_policy.service["MULTI"].xml_content)[0])
    error_message = "The JWT variables are common policies: they come before the asset classification."
  }
}

run "tool_limit_needs_tool_apis" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_limit = { calls_per_minute = 10 } }]
  }

  expect_failures = [var.services]
}

run "agent_limit_needs_agent_apis" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", agent_limit = { calls_per_minute = 10 } }]
  }

  expect_failures = [var.services]
}

run "tool_apis_must_be_granted_by_the_product" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"] }]
  }

  expect_failures = [var.services]
}

run "an_api_cannot_be_both_tool_and_agent" {
  command = plan

  variables {
    api_name_mapping = { LLM = ["universal-llm-api", "x"], DOC = ["document-intelligence-api"] }
    services         = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["x"], agent_apis = ["x"] }]
  }

  expect_failures = [var.services]
}

run "api_names_cannot_inject_xml" {
  command = plan

  variables {
    api_name_mapping = { LLM = ["a\" /><x a=\""] }
    services         = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["a\" /><x a=\""] }]
  }

  expect_failures = [var.services]
}

run "asset_limits_are_validated" {
  command = plan

  variables {
    api_name_mapping = { LLM = ["universal-llm-api", "weather-mcp"] }
    services         = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"], tool_limit = { calls_per_minute = 0 } }]
  }

  expect_failures = [var.services]
}

run "asset_limit_period_is_validated" {
  command = plan

  variables {
    api_name_mapping = { LLM = ["universal-llm-api", "weather-mcp"] }
    services         = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"], tool_limit = { call_quota = 5, call_quota_period = "Fortnightly" } }]
  }

  expect_failures = [var.services]
}
