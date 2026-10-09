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

# Foundry embeddings deployment for the semantic cache.
resource "azapi_resource" "embeddings_backend" {
  count     = var.features.embeddings_backend && var.embeddings_backend_url != "" ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "embeddings-backend"
  parent_id = local.apim_id

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
          clientId = data.azurerm_user_assigned_identity.apim.client_id
          resource = "https://cognitiveservices.azure.com"
        }
      }
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
