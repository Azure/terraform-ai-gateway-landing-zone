# Model-aware static fragments, OWNED HERE (review 7.8). The routing fragments
# come from modules/llm-routing; the model-agnostic ones from gateway-config.

locals {
  fragments_dir = "${path.module}/fragments"

  llm_fragments = merge(
    {
      "set-backend-authorization" = "Authentication and routing configuration for different LLM backend types"
      "set-target-backend-pool"   = "Determines the target backend pool for LLM requests"
      "set-llm-usage"             = "Collects usage metrics for LLM requests"
      "set-llm-requested-model"   = "Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)"
      "validate-model-access"     = "Validates that the requested model is in the allowed models list for the product"
      "responses-id-security"     = "Per-subscription ownership enforcement for the Responses API"
      "responses-id-cache-store"  = "Records ownership of newly created Responses API objects"
      "ai-foundry-deployments"    = "AI Foundry deployments helper fragment"
    },
    var.features.unified_ai_api ? {
      "central-cache-manager" = "Caches metadata configuration for Unified AI API"
      "request-processor"     = "Analyzes incoming Unified AI requests"
      "path-builder"          = "Reconstructs backend URI paths for Unified AI API"
    } : {},
  )

  # gateway-config fragments the LLM policies include.
  required_shared_fragments = toset(["security-handler", "raise-throttling-events", "set-response-headers", "strip-backend-headers", "ai-foundry-compatibility"])
}

module "llm_fragments" {
  source = "../../modules/apim-policy-fragments"

  api_management_id = local.apim_id

  fragments = {
    for k, d in local.llm_fragments : k => {
      xml         = file("${local.fragments_dir}/frag-${k}.xml")
      description = d
    }
  }

  # set-backend-authorization references the aws-* and backend key named values.
  depends_on_ids = concat(
    [for nv in azurerm_api_management_named_value.aws : nv.id],
    [azurerm_api_management_named_value.aws_region.id],
    [for nv in azurerm_api_management_named_value.backend_api_key : nv.id],
  )
}
