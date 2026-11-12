# =============================================================================
# GATEWAY ENTRA APP — the application APIM validates JWTs against
# (validate-jwt / validate-azure-ad-token). No client secret: the gateway only
# needs the tenant ID, client ID and audience.
#
# Creates the app registration (access_as_user scope + the Model.Invoke,
# MCP.Invoke and Agent.Invoke roles), its identifier URI and service
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
  # Canonical IDs (mirrors setup.ps1 and scripts/entra_id_setup.py so re-runs hit the same IDs). The Invoke
  # roles keep the IDs of the Models.Read, MCP.Read and Agent.Read roles they replace, so an existing app is
  # updated in place and its role assignments survive.
  role_access_as_user = "00000000-0000-0000-0000-000000000001"
  role_model_invoke   = "00000000-0000-0000-0000-000000000003"
  role_mcp_invoke     = "00000000-0000-0000-0000-000000000004"
  role_agent_invoke   = "00000000-0000-0000-0000-000000000005"
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
    id                   = local.role_model_invoke
    allowed_member_types = ["User", "Application"]
    display_name         = "Model.Invoke"
    description          = "Invoke LLM model endpoints (chat completions, embeddings)"
    enabled              = true
    value                = "Model.Invoke"
  }

  app_role {
    id                   = local.role_mcp_invoke
    allowed_member_types = ["User", "Application"]
    display_name         = "MCP.Invoke"
    description          = "Invoke MCP tool endpoints"
    enabled              = true
    value                = "MCP.Invoke"
  }

  app_role {
    id                   = local.role_agent_invoke
    allowed_member_types = ["User", "Application"]
    display_name         = "Agent.Invoke"
    description          = "Invoke agent endpoints"
    enabled              = true
    value                = "Agent.Invoke"
  }

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
  }

  # azuread_application_identifier_uri owns the identifier URI: without this every plan would remove
  # api://<client_id> again, and clients request their tokens for api://<client_id>/.default.
  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

# api://<client_id> — split into its own resource to avoid self-reference cycle
resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = "api://${azuread_application.gateway.client_id}"
}

resource "azuread_service_principal" "gateway" {
  client_id = azuread_application.gateway.client_id
  # Same owners as the app: deleting (and managing) a service principal needs its owner or an
  # Entra admin role, so without owners whoever applied this stack couldn't destroy it.
  owners = azuread_application.gateway.owners
}
