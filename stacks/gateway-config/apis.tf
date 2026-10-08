# Service APIs (model-agnostic). The LLM APIs belong to llm-backend-onboarding.
# Assets live in apis/<name>/; a for_each instance can't depend on a sibling
# instance, so APIs that need another API or a backend go in the second wave.

locals {
  apis_dir = "${path.module}/apis"

  # API keys travel in the api-key header unless Entra auth replaces them.
  api_key_names          = { header = "api-key", query = "api-key" }
  subscription_key_names = { header = "Ocp-Apim-Subscription-Key", query = "subscription-key" }

  azure_monitor_no_body = {
    request  = { headers = [], body = { bytes = 0 } }
    response = { headers = [], body = { bytes = 0 } }
  }

  service_app_insights_diagnostic = var.api_diagnostics.enabled ? {
    logger_id  = local.app_insights_logger_id
    verbosity  = "information"
    body_bytes = var.api_diagnostics.body_bytes
    headers    = var.api_diagnostics.headers
  } : null

  service_azure_monitor_diagnostic = var.api_diagnostics.enabled ? {
    response_export_values = null
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "Information"
      logClientIp = true
      loggerId    = local.azure_monitor_logger_id
      sampling    = { samplingType = "fixed", percentage = 100 }
      frontend    = local.azure_monitor_no_body
      backend     = local.azure_monitor_no_body
      largeLanguageModel = {
        logs      = "enabled"
        requests  = { messages = "all", maxSizeInBytes = 262144 }
        responses = { messages = "all", maxSizeInBytes = 262144 }
      }
    }
  } : null

  first_wave_raw = merge(
    var.features.azure_ai_search ? {
      "azure-ai-search-index-api" = {
        api = {
          name                   = "azure-ai-search-index-api"
          display_name           = "Azure AI Search Index API (index services)"
          description            = "Azure AI Search Index Client APIs"
          path                   = "search"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth.enabled
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file("${local.apis_dir}/azure-ai-search-index-api/ai-search-index-2024-07-01-api-spec.json") }
          policy_xml             = file("${local.apis_dir}/azure-ai-search-index-api/ai-search-index-api-policy.xml")
        }
        app_insights_diagnostic  = local.service_app_insights_diagnostic
        azure_monitor_diagnostic = local.service_azure_monitor_diagnostic
      }
    } : {},
    var.features.document_intelligence ? {
      "document-intelligence-api-legacy" = {
        api = {
          name                   = "document-intelligence-api-legacy"
          display_name           = "Document Intelligence API (Legacy)"
          description            = "Uses (/formrecognizer) url path. Extracts content, layout, and structured data from documents."
          path                   = "formrecognizer"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth.enabled
          subscription_key_names = local.subscription_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/document-intelligence-api/document-intelligence-2024-11-30-compressed.openapi.yaml") }
          policy_xml             = file("${local.apis_dir}/document-intelligence-api/doc-intelligence-api-policy.xml")
        }
        app_insights_diagnostic  = local.service_app_insights_diagnostic
        azure_monitor_diagnostic = local.service_azure_monitor_diagnostic
      }
    } : {},
    var.features.mcp_sample ? {
      "weather-api" = {
        api = {
          name                  = "weather-api"
          display_name          = "Weather API"
          description           = "Sample Weather API used to demonstrate the MCP-from-API pattern."
          path                  = "weather"
          subscription_required = false
          spec                  = { format = "openapi+json", value = file("${local.apis_dir}/weather-api/openapi.json") }
          policy_xml            = file("${local.apis_dir}/weather-api/policy.xml")
        }
      }
    } : {},
  )

  second_wave_raw = merge(
    var.features.document_intelligence ? {
      "document-intelligence-api" = {
        api = {
          name                   = "document-intelligence-api"
          display_name           = "Document Intelligence API"
          description            = "Uses (/documentintelligence) url path. Extracts content, layout, and structured data from documents."
          path                   = "documentintelligence"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth.enabled
          subscription_key_names = local.subscription_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/document-intelligence-api/document-intelligence-2024-11-30-compressed.openapi.yaml") }
          policy_xml             = file("${local.apis_dir}/document-intelligence-api/doc-intelligence-api-policy.xml")
        }
        app_insights_diagnostic  = local.service_app_insights_diagnostic
        azure_monitor_diagnostic = local.service_azure_monitor_diagnostic
        api_depends_on           = [module.api["document-intelligence-api-legacy"].id] # same spec as the legacy API
      }
    } : {},
    var.features.mcp_sample ? {
      "weather-mcp" = {
        api = {
          name                    = "weather-mcp"
          type                    = "mcp"
          azapi_schema_validation = false
          policy_xml              = file("${local.apis_dir}/shared/mcp-default-policy.xml")
          azapi_properties_json = jsonencode({
            type                 = "mcp"
            displayName          = "Weather MCP"
            description          = "MCP server derived from the Weather sample API."
            subscriptionRequired = false
            path                 = "weather-mcp"
            protocols            = ["https"]
            mcpTools = [
              for op_id in ["get-weather"] : {
                name        = op_id
                operationId = "${local.apim_id}/apis/${module.api["weather-api"].name}/operations/${op_id}"
                description = "Weather MCP tool derived from ${op_id}"
              }
            ]
          })
        }
        api_depends_on = [module.api["weather-api"].id]
      }
      "ms-learn-mcp" = {
        api = {
          name                    = "ms-learn-mcp"
          type                    = "mcp"
          azapi_schema_validation = false
          policy_xml              = file("${local.apis_dir}/shared/mcp-default-policy.xml")
          azapi_properties_json = jsonencode({
            type                 = "mcp"
            displayName          = "Microsoft Learn MCP"
            description          = "Microsoft Learn MCP server"
            subscriptionRequired = false
            path                 = "ms-learn-mcp"
            protocols            = ["https"]
            backendId            = "ms-learn-mcp-backend"
            mcpPropperties = {
              transportType = "streamable"
            }
          })
        }
        api_depends_on = [azapi_resource.ms_learn_mcp_backend[0].id]
      }
    } : {},
  )

  # One shape for every catalogue entry (for_each values must share a type).
  api_defaults = {
    type                    = "http"
    display_name            = null
    description             = null
    path                    = null
    protocols               = ["https"]
    service_url             = null
    subscription_required   = true
    subscription_key_names  = null
    spec                    = null
    policy_xml              = null
    azapi_properties_json   = null
    azapi_schema_validation = true
  }
  api_entry_defaults = {
    operation_policies       = {}
    azapi_operation_policies = {}
    app_insights_diagnostic  = null
    azure_monitor_diagnostic = null
    product                  = null
    api_depends_on           = []
  }
  first_wave  = { for k, v in local.first_wave_raw : k => merge(local.api_entry_defaults, v, { api = merge(local.api_defaults, v.api) }) }
  second_wave = { for k, v in local.second_wave_raw : k => merge(local.api_entry_defaults, v, { api = merge(local.api_defaults, v.api) }) }

  # APIM validates fragment / named-value references when a policy is saved.
  api_policy_depends_on = concat(
    values(module.shared_fragments.ids),
    [for nv in azurerm_api_management_named_value.plain : nv.id],
  )
}

module "api" {
  source   = "../../modules/gateway-api"
  for_each = local.first_wave

  api_management_id   = local.apim_id
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name

  api                      = each.value.api
  operation_policies       = each.value.operation_policies
  azapi_operation_policies = each.value.azapi_operation_policies
  app_insights_diagnostic  = each.value.app_insights_diagnostic
  azure_monitor_diagnostic = each.value.azure_monitor_diagnostic
  product                  = each.value.product
  policy_depends_on        = local.api_policy_depends_on
}

module "api_dependent" {
  source   = "../../modules/gateway-api"
  for_each = local.second_wave

  api_management_id   = local.apim_id
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name

  api                      = each.value.api
  operation_policies       = each.value.operation_policies
  azapi_operation_policies = each.value.azapi_operation_policies
  app_insights_diagnostic  = each.value.app_insights_diagnostic
  azure_monitor_diagnostic = each.value.azure_monitor_diagnostic
  product                  = each.value.product
  api_depends_on           = each.value.api_depends_on
  policy_depends_on        = local.api_policy_depends_on
}
