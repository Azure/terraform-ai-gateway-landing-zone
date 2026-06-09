# =============================================================================
# FOUNDRY → APIM CONNECTION — Bicep parity:
#   foundry-integration/connection-apim.bicep
#   foundry-integration/modules/apim-connection-common.bicep
#
# Creates a Microsoft.CognitiveServices/accounts/projects/connections
# resource per (project, api) pair so Foundry can call APIM via ApiKey.
# =============================================================================

locals {
  # Flatten: for each enabled connection entry × each Foundry project.
  apim_connection_pairs = var.enable_apim_connections ? flatten([
    for pi, p in local.instances : [
      for c in var.apim_connections : {
        key                = "${local.instance_names[pi]}-${c.api_name}"
        project_index      = pi
        api_name           = c.api_name
        api_path           = c.api_path
        connection_name    = c.connection_name != "" ? c.connection_name : "apim-${var.apim_service_name}-${c.api_name}"
        is_shared_to_all   = c.is_shared_to_all
        deployment_in_path = c.deployment_in_path
        inference_api_version = c.inference_api_version
        deployment_api_version = c.deployment_api_version
        list_models_endpoint   = c.list_models_endpoint
        get_model_endpoint     = c.get_model_endpoint
        deployment_provider    = c.deployment_provider
        static_models          = c.static_models
        custom_headers         = c.custom_headers
      }
    ]
  ]) : []

  apim_connection_map = { for pair in local.apim_connection_pairs : pair.key => pair }
}

resource "azapi_resource" "apim_connection" {
  for_each = local.apim_connection_map

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = each.value.connection_name
  parent_id = azapi_resource.project[each.value.project_index].id

  schema_validation_enabled = false

  body = {
    properties = merge(
      {
        category      = "ApiManagement"
        target        = "${var.apim_gateway_url}/${each.value.api_path}"
        authType      = "ApiKey"
        isSharedToAll = each.value.is_shared_to_all
        credentials = {
          key = var.apim_primary_key
        }
      },
      {
        metadata = merge(
          {
            deploymentInPath = each.value.deployment_in_path
          },
          each.value.inference_api_version != "" ? {
            inferenceAPIVersion = each.value.inference_api_version
          } : {},
          each.value.deployment_api_version != "" ? {
            deploymentAPIVersion = each.value.deployment_api_version
          } : {},
          (each.value.list_models_endpoint != "" && each.value.get_model_endpoint != "" && each.value.deployment_provider != "") ? {
            modelDiscovery = jsonencode({
              listModelsEndpoint = each.value.list_models_endpoint
              getModelEndpoint   = each.value.get_model_endpoint
              deploymentProvider = each.value.deployment_provider
            })
          } : {},
          length(each.value.static_models) > 0 ? {
            models = jsonencode(each.value.static_models)
          } : {},
          length(each.value.custom_headers) > 0 ? {
            customHeaders = jsonencode(each.value.custom_headers)
          } : {}
        )
      }
    )
  }

  depends_on = [azapi_resource.project]
}
