# Model-agnostic shared fragments, OWNED HERE (review 7.8). Model-aware and
# routing fragments belong to llm-backend-onboarding. Add a fragment by adding
# fragments/frag-<name>.xml and an entry below.

locals {
  fragments_dir = "${path.module}/fragments"

  shared_fragments = {
    "ai-usage"                 = "Tracks usage of all AI-related APIs"
    "raise-throttling-events"  = "Raises custom events when throttling limits are hit"
    "throttling-events"        = "Throttling events configuration"
    "security-handler"         = "Unified authentication handler for all AI Gateway APIs"
    "entra-auth"               = "Entra ID authentication fragment"
    "aad-auth"                 = "AAD auth fragment"
    "aad-auth-custom"          = "AAD auth (custom) fragment"
    "llm-usage"                = "LLM usage tracking"
    "openai-usage"             = "OpenAI usage tracking"
    "openai-usage-streaming"   = "OpenAI streaming usage tracking"
    "ai-foundry-compatibility" = "Foundry CORS compatibility"
    "set-response-headers"     = "Adds UAIG-* response headers"
    "strip-backend-headers"    = "Removes browser, App Service/ARR, and X-Forwarded-* headers before forwarding to AI backends"
  }

  # PII fragments use policy elements azurerm doesn't validate yet (azapi).
  pii_fragments = var.features.pii_anonymization ? {
    "pii-anonymization"   = "Anonymizes PII in API requests"
    "pii-deanonymization" = "Deanonymizes PII in API responses"
    "pii-state-saving"    = "Saves PII state for testing"
  } : {}
}

module "shared_fragments" {
  source = "../../modules/apim-policy-fragments"

  api_management_id = local.apim_id

  fragments = {
    for k, d in local.shared_fragments : k => {
      xml         = file("${local.fragments_dir}/frag-${k}.xml")
      description = d
    }
  }

  azapi_fragments = {
    for k, d in local.pii_fragments : k => {
      xml         = file("${local.fragments_dir}/frag-${k}.xml")
      description = d
    }
  }

  # APIM validates named-value references when a fragment is saved.
  depends_on_ids = [for nv in azurerm_api_management_named_value.plain : nv.id]
}
