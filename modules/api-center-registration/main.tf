# =============================================================================
# API CENTER REGISTRATION — Bicep parity: api-center-onboarding.bicep
# Registers each API in API Center with a Version, a Definition and a
# Deployment that points at the APIM gateway.
# =============================================================================

resource "azapi_resource" "apic_api" {
  for_each = var.enabled ? var.apis : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview"
  name      = each.key
  parent_id = "${var.api_center_id}/workspaces/${var.workspace_name}"

  body = {
    properties = {
      title            = each.value.display_name
      kind             = each.value.kind
      contacts         = []
      customProperties = {}
      summary          = each.value.description
      description      = each.value.description
    }
  }
}

resource "azapi_resource" "apic_api_version" {
  for_each = var.enabled ? var.apis : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview"
  name      = "1-0-0"
  parent_id = azapi_resource.apic_api[each.key].id

  body = {
    properties = {
      title          = "1.0.0"
      lifecycleStage = "development"
    }
  }
}

resource "azapi_resource" "apic_api_definition" {
  for_each = var.enabled ? var.apis : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview"
  name      = "${each.key}-definition"
  parent_id = azapi_resource.apic_api_version[each.key].id

  body = {
    properties = {
      description = "${each.value.display_name} Definition for version 1-0-0"
      title       = "${each.value.display_name} Definition"
    }
  }
}

resource "azapi_resource" "apic_api_deployment" {
  for_each = var.enabled ? var.apis : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview"
  name      = "${each.key}-deployment"
  parent_id = azapi_resource.apic_api[each.key].id

  body = {
    properties = {
      description   = "${each.value.display_name} Deployment"
      title         = "${each.value.display_name} Deployment"
      environmentId = "/workspaces/${var.workspace_name}/environments/${each.value.environment}"
      definitionId  = "/workspaces/${var.workspace_name}/apis/${each.key}/versions/1-0-0/definitions/${each.key}-definition"
      state         = "active"
      server = {
        runtimeUri = ["${var.gateway_url}/${each.value.path}"]
      }
    }
  }

  depends_on = [azapi_resource.apic_api_definition]
}
