# =============================================================================
# APIM BACKENDS — Bicep parity for:
#   llm-backends.bicep, llm-backend-pools.bicep, inference-backend.bicep
#   (contentSafetyBackend, aiSearchBackends, embeddingsBackend in apim.bicep)
#
# azurerm_api_management_backend is used for simple backends. For "Pool"
# type backends (load balancer), azurerm lacks support so we use azapi_resource
# at API version `2024-06-01-preview`.
# =============================================================================

# -----------------------------------------------------------------------------
# CONTENT SAFETY BACKEND — apim.bicep contentSafetyBackend
# -----------------------------------------------------------------------------

resource "azapi_resource" "content_safety_backend" {
  count     = var.enable_content_safety ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "content-safety-backend"
  parent_id = local.apim.id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Content Safety Service Backend"
      url         = var.content_safety_endpoint
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
      credentials = {
        managedIdentity = {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# AI SEARCH BACKENDS — apim.bicep aiSearchBackends
# -----------------------------------------------------------------------------

resource "azurerm_api_management_backend" "ai_search" {
  for_each = var.enable_azure_ai_search ? { for s in var.ai_search_instances : s.name => s } : {}

  name                = each.value.name
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  protocol            = "http"
  url                 = each.value.url
  description         = each.value.description

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

# -----------------------------------------------------------------------------
# EMBEDDINGS BACKEND (for semantic cache) — apim.bicep embeddingsBackend
# -----------------------------------------------------------------------------

resource "azapi_resource" "embeddings_backend" {
  count     = var.enable_embeddings_backend && var.embeddings_backend_url != "" ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = var.embeddings_backend_id
  parent_id = local.apim.id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Foundry embeddings backend for semantic cache"
      url         = var.embeddings_backend_url
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
      credentials = {
        managedIdentity = {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# MS LEARN MCP BACKEND — target of the ms-learn-mcp API (root apis.tf)
# -----------------------------------------------------------------------------

resource "azapi_resource" "ms_learn_mcp_backend" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "ms-learn-mcp-backend"
  parent_id = local.apim.id

  body = {
    properties = {
      description = "MS Learn MCP server backend"
      url         = var.ms_learn_mcp_backend_url
      protocol    = "http"
    }
  }
}
