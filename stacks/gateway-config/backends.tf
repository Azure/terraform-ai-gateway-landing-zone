# Non-LLM backends (LLM backends and pools belong to llm-backend-onboarding).

resource "azapi_resource" "content_safety_backend" {
  count     = var.features.content_safety ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "content-safety-backend"
  parent_id = local.apim_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Content Safety Service Backend"
      url         = local.content_safety_endpoint
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
      credentials = {
        managedIdentity = {
          clientId = data.azurerm_user_assigned_identity.apim.client_id
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

resource "azurerm_api_management_backend" "ai_search" {
  #checkov:skip=CKV_AZURE_215:protocol "http" is the APIM backend type (HTTP vs SOAP); the AI Search URL itself is https.
  for_each = var.features.azure_ai_search ? { for s in var.ai_search_instances : s.name => s } : {}

  name                = each.value.name
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name
  protocol            = "http"
  url                 = each.value.endpoint
  description         = "AI Search backend"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

# Embeddings deployment for the semantic cache (llm-semantic-cache-lookup embeddings-backend-id).
# No credentials: the lookup calls it as APIM's system-assigned identity (embeddings-backend-auth
# = system-assigned, the only option), which stacks/platform grants Cognitive Services OpenAI User.
# The URL is the full embeddings endpoint without a query string; the lookup adds api-version.
resource "azapi_resource" "embeddings_backend" {
  count     = var.semantic_cache.enabled ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "embeddings-backend"
  parent_id = local.apim_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Embeddings deployment for the semantic cache"
      url         = local.embeddings_url
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.embeddings_url != ""
      error_message = "semantic_cache.enabled: no embeddings endpoint. Deploy Foundry in stacks/platform (the primary account is used), or set semantic_cache.embeddings_url."
    }
  }
}

# Target of the ms-learn-mcp API.
resource "azapi_resource" "ms_learn_mcp_backend" {
  count     = var.features.mcp_sample ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "ms-learn-mcp-backend"
  parent_id = local.apim_id

  body = {
    properties = {
      description = "MS Learn MCP server backend"
      url         = var.ms_learn_mcp_backend_url
      protocol    = "http"
    }
  }
}
