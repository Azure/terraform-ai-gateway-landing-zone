# =============================================================================
# SHARED POLICY FRAGMENTS (was modules/apim/policy-fragments.tf)
# Model-agnostic and model-aware static fragments. XML lives in
# policies/fragments/ (single copy, also read by llm-backend-onboarding).
# The generated routing fragments are in modules/llm-routing.
# =============================================================================

locals {
  static_fragments = {
    "set-backend-authorization" = {
      description = "Authentication and routing configuration for different LLM backend types"
      file        = "frag-set-backend-authorization.xml"
    }
    "set-target-backend-pool" = {
      description = "Determines the target backend pool for LLM requests"
      file        = "frag-set-target-backend-pool.xml"
    }
    "set-llm-usage" = {
      description = "Collects usage metrics for LLM requests"
      file        = "frag-set-llm-usage.xml"
    }
    "set-llm-requested-model" = {
      description = "Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)"
      file        = "frag-set-llm-requested-model.xml"
    }
    "validate-model-access" = {
      description = "Validates that the requested model is in the allowed models list for the product"
      file        = "frag-validate-model-access.xml"
    }
    "ai-usage" = {
      description = "Tracks usage of all AI-related APIs"
      file        = "frag-ai-usage.xml"
    }
    "raise-throttling-events" = {
      description = "Raises custom events when throttling limits are hit"
      file        = "frag-raise-throttling-events.xml"
    }
    "throttling-events" = {
      description = "Throttling events configuration"
      file        = "frag-throttling-events.xml"
    }
    "security-handler" = {
      description = "Unified authentication handler for all AI Gateway APIs"
      file        = "frag-security-handler.xml"
    }
    "entra-auth" = {
      description = "Entra ID authentication fragment"
      file        = "frag-entra-auth.xml"
    }
    "aad-auth" = {
      description = "AAD auth fragment"
      file        = "frag-aad-auth.xml"
    }
    "aad-auth-custom" = {
      description = "AAD auth (custom) fragment"
      file        = "frag-aad-auth-custom.xml"
    }
    "ai-foundry-deployments" = {
      description = "AI Foundry deployments helper fragment"
      file        = "frag-ai-foundry-deployments.xml"
    }
    "llm-usage" = {
      description = "LLM usage tracking"
      file        = "frag-llm-usage.xml"
    }
    "openai-usage" = {
      description = "OpenAI usage tracking"
      file        = "frag-openai-usage.xml"
    }
    "openai-usage-streaming" = {
      description = "OpenAI streaming usage tracking"
      file        = "frag-openai-usage-streaming.xml"
    }
    # Referenced unconditionally by universal-llm-api-policy-v2.xml and
    # azure-open-ai-api-policy.xml, so must always be created even when the
    # PII / Unified AI feature flags are off.
    "ai-foundry-compatibility" = {
      description = "Foundry CORS compatibility"
      file        = "frag-ai-foundry-compatibility.xml"
    }
    "set-response-headers" = {
      description = "Adds UAIG-* response headers"
      file        = "frag-set-response-headers.xml"
    }
    "responses-id-security" = {
      description = "Per-subscription ownership enforcement for the Responses API"
      file        = "frag-responses-id-security.xml"
    }
    "responses-id-cache-store" = {
      description = "Records ownership of newly created Responses API objects"
      file        = "frag-responses-id-cache-store.xml"
    }
    "strip-backend-headers" = {
      description = "Removes browser, App Service/ARR, and X-Forwarded-* headers before forwarding to AI backends"
      file        = "frag-strip-backend-headers.xml"
    }
  }

  pii_fragments = local.features.pii_anonymization ? {
    "pii-anonymization" = {
      description = "Anonymizes PII in API requests"
      file        = "frag-pii-anonymization.xml"
    }
    "pii-deanonymization" = {
      description = "Deanonymizes PII in API responses"
      file        = "frag-pii-deanonymization.xml"
    }
    "pii-state-saving" = {
      description = "Saves PII state for testing"
      file        = "frag-pii-state-saving.xml"
    }
  } : {}

  unified_ai_fragments = local.features.unified_ai_api ? {
    "central-cache-manager" = {
      description = "Caches metadata configuration for Unified AI API"
      file        = "frag-central-cache-manager.xml"
    }
    "request-processor" = {
      description = "Analyzes incoming Unified AI requests"
      file        = "frag-request-processor.xml"
    }
    "path-builder" = {
      description = "Reconstructs backend URI paths for Unified AI API"
      file        = "frag-path-builder.xml"
    }
  } : {}

  all_static_fragments = merge(local.static_fragments, local.unified_ai_fragments)
}


locals {
  fragments_dir = "${path.module}/policies/fragments"
}

module "policy_fragments" {
  source = "./modules/apim-policy-fragments"

  api_management_id = module.apim.apim_id

  fragments = {
    for k, f in local.all_static_fragments : k => {
      xml         = file("${local.fragments_dir}/${f.file}")
      description = f.description
    }
  }

  azapi_fragments = {
    for k, f in local.pii_fragments : k => {
      xml         = file("${local.fragments_dir}/${f.file}")
      description = f.description
    }
  }

  # APIM validates named-value references when a fragment is saved.
  depends_on_ids = module.apim.named_value_ids
}
