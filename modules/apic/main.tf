# -----------------------------------------------------------------------------
# API CENTER (AI Registry)
# Workspace + environments + metadata schemas + remote MCP server registrations
# -----------------------------------------------------------------------------

locals {
  apic_mcp_configs      = var.remote_mcp_servers
  apic_metadata_schemas = try(jsondecode(file("${path.module}/apic-metadata.json")).metadata, [])
  apic_service_name     = var.api_center_name
}

resource "azapi_resource" "api_center" {
  count     = var.enable_api_center ? 1 : 0
  type      = "Microsoft.ApiCenter/services@2024-06-01-preview"
  name      = local.apic_service_name
  parent_id = var.resource_group_id
  location  = var.apic_location
  tags      = var.tags

  schema_validation_enabled = false

  body = {
    sku = { name = var.api_center_sku }
    properties = {
      portalSettings = {
        enabled = true
      }
      siteProfile = {
        name              = "Citadel AI Registry"
        companyName       = "Citadel AI Registry"
        companyUrl        = "https://yourcompany.com"
        supportEmail      = "support@yourcompany.com"
        termsOfServiceUrl = "https://yourcompany.com/terms"
        privacyPolicyUrl  = "https://yourcompany.com/privacy"
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# The "default" workspace is auto-created by Azure when the API Center service
# is provisioned. Reference it by constructed ID rather than managing it as a
# resource.
locals {
  api_center_workspace_id = var.enable_api_center ? "${azapi_resource.api_center[0].id}/workspaces/default" : ""
}

# Metadata schemas (from apic-metadata.json)
resource "azapi_resource" "api_center_metadata_schema" {
  for_each = var.enable_api_center ? {
    for m in local.apic_metadata_schemas : m.name => m
  } : {}

  type      = "Microsoft.ApiCenter/services/metadataSchemas@2024-03-01"
  name      = each.value.name
  parent_id = azapi_resource.api_center[0].id

  body = {
    properties = {
      schema = each.value.schema
      assignedTo = [for a in each.value.assignedTo : {
        deprecated = false
        entity     = a.entity
        required   = a.required
      }]
    }
  }
}

# Environments — 2 API + 2 MCP
resource "azapi_resource" "api_center_env_api_dev" {
  count     = var.enable_api_center ? 1 : 0
  type      = "Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview"
  name      = "api-dev"
  parent_id = local.api_center_workspace_id

  body = {
    properties = {
      title       = "API Development"
      description = "API default development environment"
      kind        = "REST"
      server = {
        managementPortalUri = ["https://portal.azure.com/"]
        type                = "Development"
      }
    }
  }
}

resource "azapi_resource" "api_center_env_api_prod" {
  count     = var.enable_api_center ? 1 : 0
  type      = "Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview"
  name      = "api-prod"
  parent_id = local.api_center_workspace_id

  body = {
    properties = {
      title       = "API Production"
      description = "API default production environment"
      kind        = "REST"
      server = {
        managementPortalUri = ["https://portal.azure.com/"]
        type                = "Development"
      }
    }
  }
}

resource "azapi_resource" "api_center_env_mcp_dev" {
  count     = var.enable_api_center ? 1 : 0
  type      = "Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview"
  name      = "mcp-dev"
  parent_id = local.api_center_workspace_id

  body = {
    properties = {
      title       = "MCP Development"
      description = "mcp default development environment"
      kind        = "MCP"
      server = {
        managementPortalUri = ["https://portal.azure.com/"]
        type                = "Development"
      }
    }
  }
}

resource "azapi_resource" "api_center_env_mcp_prod" {
  count     = var.enable_api_center ? 1 : 0
  type      = "Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview"
  name      = "mcp-prod"
  parent_id = local.api_center_workspace_id

  body = {
    properties = {
      title       = "MCP Production"
      description = "mcp default production environment"
      kind        = "MCP"
      server = {
        managementPortalUri = ["https://portal.azure.com/"]
        type                = "Production"
      }
    }
  }
}

# Remote (third-party) MCP servers: an API of kind MCP, a version, a definition and a deployment each.
resource "azapi_resource" "api_center_mcp_api" {
  for_each = var.enable_api_center ? { for m in local.apic_mcp_configs : m.name => m } : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview"
  name      = each.value.name
  parent_id = local.api_center_workspace_id

  schema_validation_enabled = false

  body = {
    properties = {
      title          = "${upper(substr(each.value.name, 0, 1))}${substr(each.value.name, 1, -1)}"
      kind           = "mcp"
      lifecycleStage = "development" # API Center stores both in lowercase: other casing is a permanent diff
      externalDocumentation = concat(
        [{
          description = "Install VS Code"
          title       = "Install VS Code"
          url         = "https://insiders.vscode.dev/redirect/mcp/install?name=${each.value.name}&config={\"type\":\"sse\",\"url\":\"${each.value.url}\"}"
        }],
        each.value.documentation_url == "" ? [] : [{
          description = "${each.value.name} MCP documentation"
          title       = "${each.value.name} MCP documentation"
          url         = each.value.documentation_url
        }]
      )
      contacts         = []
      customProperties = {}
      summary          = each.value.description
      description      = each.value.description
    }
  }
}

resource "azapi_resource" "api_center_mcp_version" {
  for_each = var.enable_api_center ? { for m in local.apic_mcp_configs : m.name => m } : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview"
  name      = "1-0-0"
  parent_id = azapi_resource.api_center_mcp_api[each.key].id

  body = {
    properties = {
      title          = "1-0-0"
      lifecycleStage = "development"
    }
  }
}

resource "azapi_resource" "api_center_mcp_definition" {
  for_each = var.enable_api_center ? { for m in local.apic_mcp_configs : m.name => m } : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview"
  name      = "default"
  parent_id = azapi_resource.api_center_mcp_version[each.key].id

  body = {
    properties = {
      description = "default"
      title       = "default"
    }
  }
}

resource "azapi_resource" "api_center_mcp_deployment" {
  for_each = var.enable_api_center ? { for m in local.apic_mcp_configs : m.name => m } : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview"
  name      = "mcpdeployment"
  parent_id = azapi_resource.api_center_mcp_api[each.key].id

  body = {
    properties = {
      description   = "mcpdeployment"
      title         = "mcpdeployment"
      environmentId = "/workspaces/default/environments/api-dev"
      definitionId  = "/workspaces/default/apis/${each.key}/versions/1-0-0/definitions/default"
      state         = "active"
      server = {
        runtimeUri = [each.value.url]
      }
    }
  }

  depends_on = [azapi_resource.api_center_mcp_definition, azapi_resource.api_center_env_api_dev]
}
