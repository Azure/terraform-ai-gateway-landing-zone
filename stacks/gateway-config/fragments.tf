# Model-agnostic shared fragments, OWNED HERE (review 7.8). Model-aware and
# routing fragments belong to llm-backend-onboarding. Add a fragment by adding
# fragments/frag-<name>.xml and an entry below.

locals {
  fragments_dir = "${path.module}/fragments"

  shared_fragments = {
    "ai-usage"                 = "Tracks usage of all AI-related APIs"
    "raise-throttling-events"  = "Raises custom events when throttling limits are hit"
    "raise-alert-events"       = "Emits the AI Gateway Alert metric (throttling, quota, backend failures; opt-in auth, content-safety and PII alerts)"
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
    "set-asset-kind"           = "Classifies a request as llm, tool or agent for access-contract product policies that grant a mix of asset types"
    "mcp-usage"                = "Counts tool (MCP) requests per product and tool for the usage pipeline (include it in the policy of a published tool API)"
    "a2a-usage"                = "Counts agent (A2A) requests per product and agent for the usage pipeline (include it in the policy of a published agent API)"
  }

  # PII fragments use policy elements azurerm doesn't validate yet (azapi).
  pii_fragments = var.features.pii_anonymization ? {
    "pii-anonymization"   = "Anonymizes PII in API requests"
    "pii-deanonymization" = "Deanonymizes PII in API responses"
    "pii-state-saving"    = "Saves PII state for testing"
  } : {}

  # Semantic cache: always deployed (the LLM API policies include them); with semantic_cache off
  # they do nothing.
  semantic_cache_fragments = {
    "semantic-cache-lookup" = {
      description = "Semantic cache lookup (llm-semantic-cache-lookup) for products whose access contract enables it"
      xml = var.semantic_cache.enabled ? templatefile("${local.fragments_dir}/frag-semantic-cache-lookup.xml.tftpl", {
        score_threshold        = var.semantic_cache.score_threshold
        ignore_system_messages = tostring(var.semantic_cache.ignore_system_messages)
        max_message_count      = var.semantic_cache.max_message_count
      }) : local.semantic_cache_off
    }
    "semantic-cache-store" = {
      description = "Semantic cache store (llm-semantic-cache-store) after a lookup miss"
      xml = var.semantic_cache.enabled ? templatefile("${local.fragments_dir}/frag-semantic-cache-store.xml.tftpl", {
        ttl_seconds = var.semantic_cache.ttl_seconds
      }) : local.semantic_cache_off
    }
  }
  semantic_cache_off = "<fragment>\n    <!-- Semantic cache disabled (gateway-config semantic_cache.enabled = false). -->\n    <set-variable name=\"semanticCacheEnabled\" value=\"false\" />\n</fragment>"
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

  azapi_fragments = merge(
    {
      for k, d in local.pii_fragments : k => {
        xml         = file("${local.fragments_dir}/frag-${k}.xml")
        description = d
      }
    },
    local.semantic_cache_fragments,
  )

  # APIM validates named-value references when a fragment is saved; the semantic cache lookup
  # validates its embeddings backend.
  depends_on_ids = concat([for nv in azurerm_api_management_named_value.plain : nv.id], azapi_resource.embeddings_backend[*].id)
}
