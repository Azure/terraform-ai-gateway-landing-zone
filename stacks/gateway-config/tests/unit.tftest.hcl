# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
      name                = "apim-aigw-dev"
      resource_group_name = "rg-aigw-dev"
      gateway_url         = "https://apim-aigw-dev.azure-api.net"
    }
  }
  mock_data "azurerm_user_assigned_identity" {
    defaults = {
      client_id = "00000000-0000-0000-0000-0000000000c1"
    }
  }
  mock_data "azurerm_cognitive_account" {
    defaults = {
      endpoint = "https://aif-aigw-dev.cognitiveservices.azure.com/"
    }
  }
}
mock_provider "azapi" {
  override_during = plan

  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiCenter/services/apic-aigw-dev"
    }
  }
}
mock_provider "azuread" {
  override_during = plan

  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azuread_application" {
    defaults = {
      client_id       = "00000000-0000-0000-0000-0000000000e1"
      identifier_uris = ["api://00000000-0000-0000-0000-0000000000e1"]
    }
  }
}

variables {
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
}

run "defaults" {
  command = plan

  assert {
    condition     = data.azurerm_api_management.this.name == local.names.apim && local.names.apim == "apim-aigw-dev-${module.naming.seed}"
    error_message = "APIM is found by its deterministic name."
  }
  assert {
    condition     = local.plain_named_values["entra-auth"] == "false" && local.plain_named_values["tenant-id"] == "common" && local.plain_named_values["JWT-Issuer"] == "not-configured"
    error_message = "Entra auth off: placeholder values that still resolve."
  }
  assert {
    condition     = local.plain_named_values["piiServiceUrl"] == "https://aif-aigw-dev.cognitiveservices.azure.com/" && local.plain_named_values["contentSafetyServiceUrl"] == local.plain_named_values["piiServiceUrl"]
    error_message = "PII and Content Safety use the primary Foundry endpoint."
  }
  assert {
    condition     = length(local.shared_fragments) == 17 && length(local.pii_fragments) == 3
    error_message = "17 shared fragments + 3 PII fragments by default."
  }
  assert {
    condition     = length(module.api) == 0 && length(module.api_dependent) == 0 && length(data.azuread_application.gateway) == 0
    error_message = "No optional service APIs and no Entra lookup by default."
  }
}

run "entra_auth_uses_identity_stack_app" {
  command = plan

  variables {
    entra_auth = { enabled = true }
  }

  assert {
    condition     = length(data.azuread_application.gateway) == 1 && local.plain_named_values["client-id"] == "00000000-0000-0000-0000-0000000000e1"
    error_message = "Entra auth finds the gateway app of stacks/identity by name."
  }
  assert {
    condition     = local.plain_named_values["audience"] == "api://00000000-0000-0000-0000-0000000000e1" && local.plain_named_values["JWT-Issuer"] == "https://login.microsoftonline.com/00000000-0000-0000-0000-000000000001/v2.0"
    error_message = "Audience and issuer come from the app and tenant."
  }
  assert {
    condition     = local.plain_named_values["JWT-AppRegistrationId"] == "00000000-0000-0000-0000-0000000000e1" && local.plain_named_values["JWT-OpenIdConfigUrl"] == "https://login.microsoftonline.com/00000000-0000-0000-0000-000000000001/v2.0/.well-known/openid-configuration"
    error_message = "The security-handler's JWT named values: v2 tokens of the gateway app (aud = its client ID)."
  }
}

# Regression: entra_auth used to set subscription_required = false on the service APIs, whose
# policies don't validate a token, so AI Search and Document Intelligence became anonymous.
run "entra_auth_keeps_the_subscription_key_on_service_apis" {
  command = plan

  variables {
    entra_auth          = { enabled = true }
    features            = { azure_ai_search = true, document_intelligence = true, pii_redaction = false, content_safety = false }
    ai_search_instances = [{ name = "search-1", endpoint = "https://search-1.search.windows.net" }]
  }

  assert {
    condition = alltrue([
      for k in ["azure-ai-search-index-api", "document-intelligence-api-legacy", "document-intelligence-api"] :
      merge(local.first_wave, local.second_wave)[k].api.subscription_required
    ])
    error_message = "AI Search and Document Intelligence APIs require a subscription key whatever entra_auth says."
  }
}

run "explicit_entra_values_skip_the_lookup" {
  command = plan

  variables {
    entra_auth = { enabled = true, tenant_id = "00000000-0000-0000-0000-0000000000f1", client_id = "00000000-0000-0000-0000-0000000000f2", audience = "api://custom" }
  }

  assert {
    condition     = length(data.azuread_application.gateway) == 0 && local.plain_named_values["audience"] == "api://custom"
    error_message = "Explicit Entra values need no Graph lookup."
  }
}

run "service_apis" {
  command = plan

  variables {
    features            = { azure_ai_search = true, document_intelligence = true, mcp_sample = true, pii_redaction = false, content_safety = false }
    ai_search_instances = [{ name = "search-1", endpoint = "https://search-1.search.windows.net" }]
  }

  assert {
    condition     = sort(keys(module.api)) == tolist(["azure-ai-search-index-api", "document-intelligence-api-legacy", "weather-api"]) && sort(keys(module.api_dependent)) == tolist(["document-intelligence-api", "ms-learn-mcp", "weather-mcp"])
    error_message = "Service APIs in two waves."
  }
  assert {
    condition     = length(data.azurerm_cognitive_account.primary) == 0 && !contains(keys(local.plain_named_values), "piiServiceUrl")
    error_message = "No Foundry lookup when PII and Content Safety are off."
  }
}

# --- Language / Content Safety endpoint sources --------------------------------

run "dedicated_language_and_content_safety_accounts" {
  command = plan

  variables {
    pii_service            = { source = "dedicated" }
    content_safety_service = { source = "dedicated" }
  }
  override_data {
    target = data.azurerm_cognitive_account.language[0]
    values = { endpoint = "https://lang-aigw-dev.cognitiveservices.azure.com/" }
  }
  override_data {
    target = data.azurerm_cognitive_account.content_safety[0]
    values = { endpoint = "https://cs-aigw-dev.cognitiveservices.azure.com/" }
  }

  assert {
    condition     = local.plain_named_values["piiServiceUrl"] == "https://lang-aigw-dev.cognitiveservices.azure.com/" && local.plain_named_values["contentSafetyServiceUrl"] == "https://cs-aigw-dev.cognitiveservices.azure.com/"
    error_message = "PII uses the dedicated Language account, content safety the dedicated Content Safety account."
  }
  assert {
    condition     = length(data.azurerm_cognitive_account.primary) == 0
    error_message = "No Foundry lookup when neither feature takes its endpoint from Foundry (a deployment without Foundry)."
  }
  assert {
    condition     = azapi_resource.content_safety_backend[0].body.properties.url == "https://cs-aigw-dev.cognitiveservices.azure.com/"
    error_message = "The content-safety backend points at the dedicated account."
  }
  assert {
    condition     = data.azurerm_cognitive_account.language[0].name == local.names.language_service && data.azurerm_cognitive_account.content_safety[0].name == local.names.content_safety
    error_message = "The dedicated accounts are found by their deterministic names."
  }
}

run "explicit_urls_need_no_lookup" {
  command = plan

  variables {
    pii_service            = { source = "url", url = "https://existing-language.cognitiveservices.azure.com/" }
    content_safety_service = { source = "url", url = "https://existing-cs.cognitiveservices.azure.com/" }
  }

  assert {
    condition     = local.plain_named_values["piiServiceUrl"] == "https://existing-language.cognitiveservices.azure.com/" && local.plain_named_values["contentSafetyServiceUrl"] == "https://existing-cs.cognitiveservices.azure.com/"
    error_message = "Explicit endpoints are used as given."
  }
  assert {
    condition     = length(data.azurerm_cognitive_account.primary) == 0 && length(data.azurerm_cognitive_account.language) == 0 && length(data.azurerm_cognitive_account.content_safety) == 0
    error_message = "Nothing is looked up for explicit URLs."
  }
}

run "sources_can_be_mixed" {
  command = plan

  variables {
    content_safety_service = { source = "url", url = "https://existing-cs.cognitiveservices.azure.com/" }
  }

  assert {
    condition     = local.plain_named_values["piiServiceUrl"] == "https://aif-aigw-dev.cognitiveservices.azure.com/" && local.plain_named_values["contentSafetyServiceUrl"] == "https://existing-cs.cognitiveservices.azure.com/"
    error_message = "PII from Foundry, content safety from its own URL."
  }
}

run "features_off_need_no_endpoint_lookups" {
  command = plan

  variables {
    features               = { pii_redaction = false, pii_anonymization = false, content_safety = false }
    pii_service            = { source = "dedicated" }
    content_safety_service = { source = "dedicated" }
  }

  assert {
    condition     = length(data.azurerm_cognitive_account.primary) == 0 && length(data.azurerm_cognitive_account.language) == 0 && length(data.azurerm_cognitive_account.content_safety) == 0
    error_message = "With the features off nothing is looked up, so a deployment without these services still plans."
  }
}

run "url_source_needs_a_url" {
  command = plan

  variables {
    pii_service = { source = "url" }
  }

  expect_failures = [var.pii_service]
}

run "unknown_source_is_rejected" {
  command = plan

  variables {
    content_safety_service = { source = "nowhere" }
  }

  expect_failures = [var.content_safety_service]
}

# --- semantic cache ----------------------------------------------------------------

run "semantic_cache_off_by_default" {
  command = plan
  assert {
    condition = (
      length(azapi_resource.embeddings_backend) == 0 &&
      strcontains(local.semantic_cache_fragments["semantic-cache-lookup"].xml, "Semantic cache disabled") &&
      strcontains(local.semantic_cache_fragments["semantic-cache-store"].xml, "Semantic cache disabled")
    )
    error_message = "Off: no embeddings backend; both fragments exist (the LLM APIs include them) and do nothing."
  }
}

run "semantic_cache_on_uses_the_primary_foundry_account" {
  command = plan
  variables {
    semantic_cache = { enabled = true, score_threshold = 0.1, ttl_seconds = 600 }
  }
  assert {
    condition     = local.embeddings_url == "https://aif-aigw-dev.cognitiveservices.azure.com/openai/deployments/text-embedding-3-small/embeddings"
    error_message = "The embeddings backend targets the deployment on the primary Foundry account, without a query string."
  }
  assert {
    condition = (
      strcontains(local.semantic_cache_fragments["semantic-cache-lookup"].xml, "score-threshold=\"0.1\"") &&
      strcontains(local.semantic_cache_fragments["semantic-cache-lookup"].xml, "embeddings-backend-auth=\"system-assigned\"") &&
      strcontains(local.semantic_cache_fragments["semantic-cache-lookup"].xml, "semanticCacheEnabled") &&
      strcontains(local.semantic_cache_fragments["semantic-cache-store"].xml, "<llm-semantic-cache-store duration=\"600\" />") &&
      strcontains(local.semantic_cache_fragments["semantic-cache-store"].xml, "UAIG-Semantic-Cache")
    )
    error_message = "The lookup carries the threshold and system-assigned auth and is gated by the product; the store has the TTL."
  }
}

run "semantic_cache_explicit_embeddings_url" {
  command = plan
  variables {
    semantic_cache = { enabled = true, embeddings_url = "https://other.openai.azure.com/openai/deployments/emb/embeddings" }
  }
  assert {
    condition     = local.embeddings_url == "https://other.openai.azure.com/openai/deployments/emb/embeddings"
    error_message = "An explicit embeddings_url wins."
  }
}

run "semantic_cache_rejects_a_query_string" {
  command = plan
  variables {
    semantic_cache = { enabled = true, embeddings_url = "https://other.openai.azure.com/openai/deployments/emb/embeddings?api-version=2024-02-01" }
  }
  expect_failures = [var.semantic_cache]
}
