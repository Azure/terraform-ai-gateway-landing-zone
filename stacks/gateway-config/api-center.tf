# Registers this stack's APIs in the API Center of stacks/platform.
locals {
  api_center_targets = merge(
    var.features.azure_ai_search ? {
      "azure-ai-search-index-api" = { display_name = "Azure AI Search Index API", description = "Azure AI Search index query API", kind = "rest", path = "search", environment = "api-dev" }
    } : {},
    var.features.document_intelligence ? {
      "document-intelligence-api" = { display_name = "Document Intelligence API", description = "Document Intelligence API (documentintelligence path)", kind = "rest", path = "documentintelligence", environment = "api-dev" }
    } : {},
    var.features.mcp_sample ? {
      "weather-api"  = { display_name = "Weather API", description = "Sample Weather API", kind = "rest", path = "weather", environment = "api-dev" }
      "weather-mcp"  = { display_name = "Weather MCP", description = "MCP server derived from the Weather sample API", kind = "mcp", path = "weather-mcp", environment = "mcp-dev" }
      "ms-learn-mcp" = { display_name = "Microsoft Learn MCP", description = "Microsoft Learn MCP server", kind = "mcp", path = "ms-learn-mcp", environment = "mcp-dev" }
    } : {},
  )
}

module "api_center_registration" {
  source = "../../modules/api-center-registration"

  enabled        = var.features.api_center_onboarding
  api_center_id  = try(data.azapi_resource.api_center[0].id, "")
  workspace_name = "default"
  gateway_url    = data.azurerm_api_management.this.gateway_url
  apis           = local.api_center_targets

  depends_on = [module.api, module.api_dependent]
}
