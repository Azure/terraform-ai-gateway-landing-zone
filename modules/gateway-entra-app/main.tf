# =============================================================================
# GATEWAY ENTRA APP — the application APIM validates JWTs against
# (validate-jwt / validate-azure-ad-token). No client secret: the gateway only
# needs the tenant ID, client ID and audience.
#
# Creates the app registration (access_as_user scope + Task.ReadWrite,
# Models.Read, MCP.Read, Agent.Read roles), its identifier URI and service
# principal. The identity running Terraform is always an owner, which is what
# Application.ReadWrite.OwnedBy needs to manage the app later.
# =============================================================================

data "azuread_client_config" "current" {}

# Microsoft Graph — resolved to look up User.Read permission ID
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  # Canonical role IDs (mirrors setup.ps1 so re-runs hit the same IDs)
  role_access_as_user = "00000000-0000-0000-0000-000000000001"
  role_task_readwrite = "00000000-0000-0000-0000-000000000002"
  role_models_read    = "00000000-0000-0000-0000-000000000003"
  role_mcp_read       = "00000000-0000-0000-0000-000000000004"
  role_agent_read     = "00000000-0000-0000-0000-000000000005"
}

resource "azuread_application" "gateway" {
  display_name                   = var.display_name
  owners                         = distinct(concat([data.azuread_client_config.current.object_id], tolist(var.owners)))
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = true

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.role_access_as_user
      enabled                    = true
      type                       = "User"
      value                      = "access_as_user"
      admin_consent_description  = "Allow access to AI Hub Gateway API"
      admin_consent_display_name = "Access AI Hub Gateway API"
      user_consent_description   = "Allow access to AI Hub Gateway API"
      user_consent_display_name  = "Access AI Hub Gateway API"
    }
  }

  app_role {
    id                   = local.role_task_readwrite
    allowed_member_types = ["User", "Application"]
    display_name         = "ReadWrite"
    description          = "Full read and write access to all gateway capabilities"
    enabled              = true
    value                = "Task.ReadWrite"
  }

  app_role {
    id                   = local.role_models_read
    allowed_member_types = ["User", "Application"]
    display_name         = "Models.Read"
    description          = "Access to LLM model endpoints (chat completions, embeddings)"
    enabled              = true
    value                = "Models.Read"
  }

  app_role {
    id                   = local.role_mcp_read
    allowed_member_types = ["User", "Application"]
    display_name         = "MCP.Read"
    description          = "Access to MCP tool endpoints"
    enabled              = true
    value                = "MCP.Read"
  }

  app_role {
    id                   = local.role_agent_read
    allowed_member_types = ["User", "Application"]
    display_name         = "Agent.Read"
    description          = "Access to agent endpoints"
    enabled              = true
    value                = "Agent.Read"
  }

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
  }
}

# api://<client_id> — split into its own resource to avoid self-reference cycle
resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = "api://${azuread_application.gateway.client_id}"
}

resource "azuread_service_principal" "gateway" {
  client_id = azuread_application.gateway.client_id
}
