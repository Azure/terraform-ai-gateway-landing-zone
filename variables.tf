# =============================================================================
# AI Citadel Governance Hub - Input Variables
# =============================================================================
# Mirrors all parameters from the Bicep accelerator's main.bicepparam
# =============================================================================

# -----------------------------------------------------------------------------
# BASIC CONFIGURATION
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure Subscription ID for the deployment"
  type        = string
}

variable "environment_name" {
  description = "Environment name used for resource naming (e.g., citadel-dev, citadel-prod)"
  type        = string
  default     = "citadel-dev"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.environment_name))
    error_message = "Environment name must be 3-24 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "purge_soft_delete_on_destroy" {
  description = "If true, purge soft-deleted resources on destroy"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# RESOURCE NAMING (leave empty for auto-generated names)
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group name. Leave empty for auto-generated."
  type        = string
  default     = ""
}

variable "use_existing_resource_group" {
  description = "If true, import an existing resource group instead of creating a new one."
  type        = bool
  default     = false
}

variable "rollout_phase" {
  description = <<-EOT
    full = deploy everything configured. core = first phase of a phased rollout
    (scripts/deploy.sh --phased): forces the add-ons off (Entra ID setup, JWT,
    Foundry -> APIM connections, MCP samples, API Center onboarding) so the core
    platform converges first; the next run with "full" adds them.
  EOT
  type        = string
  default     = "full"
  nullable    = false

  validation {
    condition     = contains(["full", "core"], var.rollout_phase)
    error_message = "rollout_phase must be full or core."
  }
}

variable "skip_logic_app_code_deploy" {
  description = "Skip publishing the Logic App workflow code on this run (scripts/deploy.sh --skip-logic-app-code), e.g. when the SCM endpoint is only reachable from inside the VNet."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_telemetry" {
  description = "Let the Azure Verified Modules (AVM) send their usage telemetry to Microsoft (https://aka.ms/avm/telemetryinfo). No deployment data is sent."
  type        = bool
  default     = true
  nullable    = false
}

variable "name_overrides" {
  description = "Logical role => explicit resource name (keys: the names output of modules/naming, e.g. apim, key_vault, redis, logic_app). Empty values are ignored; the dedicated *_name variables take precedence."
  type        = map(string)
  default     = {}
}

variable "cosmos_db_account_name" {
  description = "Cosmos DB account name. Leave empty for auto-generated."
  type        = string
  default     = ""
}

variable "eventhub_namespace_name" {
  description = "Event Hub namespace name. Leave empty for auto-generated."
  type        = string
  default     = ""
}

variable "log_analytics_name" {
  description = "Log Analytics workspace name. Leave empty for auto-generated."
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Key Vault name. Leave empty for auto-generated."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# SECURITY/KEY-VAULT MODULE CONFIGURATION
# -----------------------------------------------------------------------------
variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vaults (1-90, default 7)"
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 1 and 90 days."
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection on Key Vault (prevents permanent deletion)"
  type        = bool
  default     = true

}

variable "rbac_authorization_enabled" {
  description = "Enable RBAC authorization on Key Vault"
  type        = bool
  default     = true
}

variable "network_acl_default_action" {
  description = "Default network access action for Key Vault (Allow or Deny)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acl_default_action)
    error_message = "Default action must be Allow or Deny."
  }
}

variable "kv_public_network_access_enabled" {
  description = "Enable public network access to Key Vault (true or false)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# KEY VAULT DEPLOYER IP ALLOWLIST (bootstrap break-glass)
# -----------------------------------------------------------------------------
# When `network_acl_default_action = "Deny"` and the Terraform runner is
# OUTSIDE the VNet, data-plane writes (secret create/update) fail with 403
# "Public network access is disabled ...". These variables provide an optional
# temporary allowlist so the deployer can seed secrets during bootstrap while
# keeping Deny-by-default for everyone else.
#
# Preferred long-term: run Terraform from a self-hosted agent inside the VNet.
# -----------------------------------------------------------------------------

variable "kv_deployer_ip_rules" {
  description = <<-EOT
    Optional list of public IPs / CIDRs to add to the Key Vault
    `network_acls.ip_rules` allowlist. Use to let a CI runner or admin
    workstation perform data-plane operations (secret writes) when
    `network_acl_default_action = "Deny"`.

    Accepts single IPs ("203.0.113.4") or CIDRs ("203.0.113.0/24").
    Leave empty ([]) in production; populate only for bootstrap or from a
    stable NAT-gateway egress IP.

    NOTE: when this list is non-empty (or `kv_auto_detect_deployer_ip` is
    true), the Key Vault's `public_network_access_enabled` is automatically
    forced to `true` regardless of `kv_public_network_access_enabled`,
    because Azure ignores `ip_rules` when public access is fully disabled.
    Combined with `network_acl_default_action = "Deny"` the vault still
    only accepts traffic from the allowlisted IPs + private endpoints.
  EOT
  type        = list(string)
  default     = []
}

variable "kv_auto_detect_deployer_ip" {
  description = <<-EOT
    When true, the current public IP of the machine running `terraform apply`
    is auto-detected (via https://api.ipify.org) and appended to
    `kv_deployer_ip_rules`. Convenient for local bootstrap from a developer
    laptop, but NOT recommended for CI runners with changing egress IPs.

    Default: false. Enable only when your runner IP is stable or for a
    one-shot bootstrap.
  EOT
  type        = bool
  default     = false
}

variable "create_apim_gateway_key_secret" {
  description = <<-EOT
    When true, a placeholder `apim-gateway-key` secret is written to Key Vault
    (value: "PLACEHOLDER-update-after-apim-deploy"). Default: false.

    Nothing in this Terraform stack reads the secret; it exists only for
    optional downstream tooling that pulls the APIM subscription key from KV
    directly. Notebook samples under
    `ai-hub-gateway-solution-accelerator-citadel-v1/validation/` fetch the
    real key via `az apim subscription show` instead, so this is safe to
    leave disabled.

    Enabling it requires KV data-plane write access from the deployer IP
    (see `kv_deployer_ip_rules` / `kv_auto_detect_deployer_ip`) and is the
    most common cause of 403 ForbiddenByFirewall errors on first apply.
  EOT
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# NETWORKING
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# COMPUTE SKU & SIZING
# -----------------------------------------------------------------------------

variable "api_center_sku" {
  description = "SKU for API Center service. Free tier is 'Free', paid tier is 'Standard'."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.api_center_sku)
    error_message = "SKU must be 'Free' or 'Standard'."
  }
}

variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
}

# -----------------------------------------------------------------------------
# FEATURE FLAGS
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# LOG ANALYTICS STRATEGY
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# NETWORK ACCESS SETTINGS
# -----------------------------------------------------------------------------

variable "ai_foundry_external_access" {
  description = "AI Foundry external network access"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ENTRA ID AUTHENTICATION
# -----------------------------------------------------------------------------

variable "entra_auth_enabled" {
  description = "Enable Entra ID JWT validation on APIM"
  type        = bool
  default     = false
}

variable "entra_tenant_id" {
  description = "Entra ID tenant ID for JWT validation"
  type        = string
  default     = ""
}

variable "entra_client_id" {
  description = "Entra ID client ID (application ID)"
  type        = string
  default     = ""
}

variable "entra_audience" {
  description = "Entra ID audience (resource identifier)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# AI FOUNDRY CONFIGURATION
# -----------------------------------------------------------------------------

variable "foundry_network_injection_enabled" {
  description = "Inject the Foundry Agent Service into the agent subnet (needs enable_agent_subnet = true)."
  type        = bool
  default     = true
}

variable "foundry_outbound_allowed_fqdns" {
  description = "Restrict the AI Foundry accounts' outbound network access (incl. the Agent Service) to these FQDNs. null = unrestricted. Opt-in: list every endpoint your agents and tools call."
  type        = list(string)
  default     = null
}

variable "ai_foundry_instances" {
  description = "List of AI Foundry instances to deploy"
  type = list(object({
    name                      = optional(string, "")
    location                  = string
    custom_subdomain          = optional(string, "")
    default_project_name      = optional(string, "citadel-governance-project")
    network_injection_enabled = optional(bool, true)
  }))
  default = [
    {
      location             = "eastus"
      default_project_name = "citadel-governance-project"
    }
  ]
}

variable "ai_foundry_models" {
  description = "List of models to deploy across AI Foundry instances"
  type = list(object({
    name             = string
    publisher        = optional(string, "OpenAI")
    version          = string
    sku              = optional(string, "GlobalStandard")
    capacity         = optional(number, 100)
    ai_service_index = optional(number, 0)
  }))
  default = [
    {
      name    = "gpt-4o"
      version = "2024-11-20"
    },
    {
      name    = "gpt-4o-mini"
      version = "2024-07-18"
    }
  ]
}

# -----------------------------------------------------------------------------
# LLM BACKEND CONFIGURATION
# -----------------------------------------------------------------------------

variable "llm_backend_config" {
  description = <<-EOT
    OPTIONAL — full override of APIM LLM backend configuration.

    Leave as `[]` (the default) to let the root module auto-derive backends
    from `enable_ai_foundry` + `ai_foundry_instances` + `ai_foundry_models`.
    One backend is created per Foundry instance, priority 1 for instance 0,
    priority 2 for subsequent instances; models are grouped by
    `ai_service_index`.

    Populate this variable ONLY when you need non-Foundry backends
    exclusively (e.g. external Azure OpenAI, third-party LLM gateway). When
    non-empty, it REPLACES the auto-derived list entirely.

    To keep auto-derivation AND add external backends, leave this empty and
    use `extra_llm_backends` instead.

    Each `supported_models` entry is an object (mirrors Bicep).
  EOT
  type = list(object({
    backend_id   = string
    backend_type = string # ai-foundry, azure-openai, external
    endpoint     = string
    auth_scheme  = string           # managedIdentity, apiKey, token
    auth_type    = optional(string) # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'
    auth_config = optional(object({
      named_value_key = optional(string)
    }))
    supported_models = list(object({
      name                = string
      sku                 = optional(string, "Standard")
      capacity            = optional(number, 100)
      modelFormat         = optional(string, "OpenAI")
      modelVersion        = optional(string, "1")
      apiVersion          = optional(string, "2024-02-15-preview")
      timeout             = optional(number, 120)
      inferenceApiVersion = optional(string, "")
      retirementDate      = optional(string, "")
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
  }))
  default = []
}

variable "extra_llm_backends" {
  description = <<-EOT
    OPTIONAL — APPENDED to the auto-derived Foundry backends.

    Use to mix Foundry (auto-derived) with external backends (Azure OpenAI
    outside Foundry, third-party endpoints, etc.) in the same gateway without
    losing auto-derivation. Same object shape as `llm_backend_config`.

    Ignored when `llm_backend_config` is set (full override takes precedence).
  EOT
  type = list(object({
    backend_id   = string
    backend_type = string
    endpoint     = string
    auth_scheme  = string           # managedIdentity, apiKey, token
    auth_type    = optional(string) # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'
    auth_config = optional(object({
      named_value_key = optional(string)
    }))
    supported_models = list(object({
      name                = string
      sku                 = optional(string, "Standard")
      capacity            = optional(number, 100)
      modelFormat         = optional(string, "OpenAI")
      modelVersion        = optional(string, "1")
      apiVersion          = optional(string, "2024-02-15-preview")
      timeout             = optional(number, 120)
      inferenceApiVersion = optional(string, "")
      retirementDate      = optional(string, "")
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC LOGGING
# -----------------------------------------------------------------------------

variable "apim_log_verbosity" {
  description = "APIM diagnostic log verbosity: verbose, information, error"
  type        = string
  default     = "information"
}

variable "apim_log_body_bytes" {
  description = "Max bytes to log from request/response body"
  type        = number
  default     = 8192
}

# -----------------------------------------------------------------------------
# REDIS (Azure Managed Redis) — Bicep parity (redis.bicep)
# -----------------------------------------------------------------------------

variable "redis_sku_name" {
  description = "Azure Managed Redis (Microsoft.Cache/redisEnterprise) SKU, e.g. Balanced_B10, MemoryOptimized_M10, ComputeOptimized_X5, FlashOptimized_A250, or a legacy Enterprise_E10 / EnterpriseFlash_F300."
  type        = string
  default     = "Balanced_B10"

  validation {
    condition     = can(regex("^((Balanced_B|MemoryOptimized_M|ComputeOptimized_X|FlashOptimized_A)[0-9]+|Enterprise_E[0-9]+|EnterpriseFlash_F[0-9]+)$", var.redis_sku_name))
    error_message = "redis_sku_name must be an Azure Managed Redis SKU (Balanced_B*, MemoryOptimized_M*, ComputeOptimized_X*, FlashOptimized_A*) or Enterprise_E* / EnterpriseFlash_F*."
  }
}

variable "redis_sku_capacity" {
  description = "Cluster capacity (used only for Enterprise_*/EnterpriseFlash_* SKUs)."
  type        = number
  default     = 2

  validation {
    condition     = var.redis_sku_capacity >= 1 && floor(var.redis_sku_capacity) == var.redis_sku_capacity
    error_message = "redis_sku_capacity must be a positive whole number."
  }
}

variable "redis_public_network_access" {
  description = "Enabled or Disabled for Redis public network access."
  type        = string
  default     = "Disabled"
}

variable "redis_minimum_tls_version" {
  description = "Minimum TLS version accepted by Azure Managed Redis."
  type        = string
  default     = "1.2"
}

# -----------------------------------------------------------------------------
# OPTIONAL APIM EXTRA APIs — Bicep parity (main.bicep feature flags)
# -----------------------------------------------------------------------------

variable "enable_extra_api_diagnostics" {
  description = "Attach Application Insights and Azure Monitor diagnostics to the service APIs (AI Search, Document Intelligence). The LLM APIs always have diagnostics."
  type        = bool
  default     = false
}

variable "extra_api_log_settings" {
  description = "Headers and body bytes logged by the service-API Application Insights diagnostics (Bicep parity: api.bicep logSettings)."
  type = object({
    headers = list(string)
    body    = object({ bytes = number })
  })
  default = {
    headers = ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"]
    body    = { bytes = 0 }
  }
}

variable "inference_api_type" {
  description = "Universal LLM API inference contract (Bicep: inferenceAPIType). One of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  type        = string
  default     = "OpenAIV1"
  validation {
    condition     = contains(["AzureOpenAI", "AzureAI", "OpenAI", "OpenAIV1"], var.inference_api_type)
    error_message = "inference_api_type must be one of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  }
}

# -----------------------------------------------------------------------------
# API CENTER — Bicep parity
# -----------------------------------------------------------------------------

variable "apic_location" {
  description = "Override region for API Center (APIC may not be available in every region)."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# AI SEARCH INSTANCES (Bicep parity: aiSearchInstances)
# -----------------------------------------------------------------------------

variable "ai_search_instances" {
  description = "Optional list of existing AI Search endpoints to register as APIM backends."
  type = list(object({
    name     = string
    endpoint = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# AZURE MONITOR PRIVATE LINK SCOPE (Bicep parity: useAzureMonitorPrivateLinkScope)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# DIAGNOSTIC BODY-BYTE OVERRIDES (Bicep parity: azureMonitorLogSettings / appInsightsLogSettings)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# FOUNDRY EMBEDDINGS MODEL (Bicep parity: primaryFoundryEmbeddingModelName)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ENTRA / AUTH SECRETS (Bicep parity: entraClientSecret)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# LOGIC APP CONTENT SHARE (Bicep parity: logicContentShareName)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# APIM LOGIC PLANE — Bicep parity (§19.12)
# -----------------------------------------------------------------------------

variable "configure_circuit_breaker" {
  description = "Enable per-backend circuit breaker rules."
  type        = bool
  default     = true
}

variable "ms_learn_mcp_backend_url" {
  description = "Backend URL for MS Learn MCP server (consumed only when is_mcp_sample_deployed = true)."
  type        = string
  default     = "https://learn.microsoft.com/api/mcp"
}

variable "enable_jwt_auth" {
  description = "Populate JWT-* named values (TenantId/AppRegistrationId/Issuer/OpenIdConfigUrl)."
  type        = bool
  default     = false
}

variable "jwt_tenant_id" {
  description = "Entra tenant ID used by the APIM JWT-validation policies. Ignored when enable_entra_id_setup = true (the setup's tenant is used)."
  type        = string
  default     = ""
}

variable "jwt_app_registration_id" {
  description = "Entra application (client) ID used as the JWT audience. Ignored when enable_entra_id_setup = true (the created app is used)."
  type        = string
  default     = ""
}

variable "azure_login_endpoint" {
  description = "Entra login endpoint (default: Azure public cloud)."
  type        = string
  default     = "https://login.microsoftonline.com/"
}

# -----------------------------------------------------------------------------
# Entra ID add-on (Bicep parity: entra-id-setup/setup.ps1)
# -----------------------------------------------------------------------------
variable "enable_entra_id_setup" {
  description = "Port of entra-id-setup/setup.ps1. When true, creates an app registration + service principal + client secret and writes the secret to Key Vault; the app's client_id/tenant overrides jwt_* variables and populates APIM JWT-* named values."
  type        = bool
  default     = false
}

variable "entra_app_display_name_prefix" {
  description = "Prefix for the Entra ID app registration display name (suffixed with environment_name)."
  type        = string
  default     = "ai-citadel-gateway"
}

variable "entra_client_secret_name" {
  description = "Key Vault secret name used to store the Entra ID app client secret."
  type        = string
  default     = "ENTRA-APP-CLIENT-SECRET"
}

variable "entra_client_secret_rotation_days" {
  description = "Rotate the Entra ID client secret after this many days (default: 2 years). Must be <= 90 in Azure Landing Zone subscriptions (Enforce-GR-KeyVault)."
  type        = number
  default     = 730
}

variable "enable_foundry_apim_connection" {
  description = "Create a dedicated APIM subscription (foundry-apim-connection) and, for every Foundry project, one ApiManagement connection per entry in foundry_apim_connections that authenticates with that subscription's key."
  type        = bool
  default     = false
}

variable "foundry_apim_connections" {
  description = <<-EOT
    APIs to expose to each Foundry project as ApiManagement connections (used
    when enable_foundry_apim_connection = true). Default: the Universal LLM API
    with dynamic model discovery via its /deployments operations.
  EOT
  type = list(object({
    api_name               = string
    api_path               = string
    connection_name        = optional(string, "")
    is_shared_to_all       = optional(bool, false)
    deployment_in_path     = optional(string, "true")
    inference_api_version  = optional(string, "")
    deployment_api_version = optional(string, "")
    list_models_endpoint   = optional(string, "")
    get_model_endpoint     = optional(string, "")
    deployment_provider    = optional(string, "")
    static_models          = optional(list(any), [])
    custom_headers         = optional(map(string), {})
  }))
  default = [
    {
      api_name             = "universal-llm-api"
      api_path             = "models"
      deployment_in_path   = "false"
      list_models_endpoint = "/deployments"
      get_model_endpoint   = "/deployments/{deploymentName}"
      deployment_provider  = "AzureOpenAI"
    }
  ]
}

variable "embeddings_backend_url" {
  description = "Foundry embeddings deployment endpoint (consumed only when enable_embeddings_backend = true)."
  type        = string
  default     = ""
}
