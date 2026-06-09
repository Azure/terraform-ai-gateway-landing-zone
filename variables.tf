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

variable "apim_service_name" {
  description = "API Management service name. Leave empty for auto-generated."
  type        = string
  default     = ""
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

variable "use_existing_vnet" {
  description = "Use an existing VNet instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_vnet_rg" {
  description = "Resource group of the existing VNet (required if use_existing_vnet = true)"
  type        = string
  default     = ""
}

variable "vnet_name" {
  description = "VNet name (existing or new)"
  type        = string
  default     = ""
}

variable "vnet_address_prefix" {
  description = "Address prefix for new VNet"
  type        = string
  default     = "10.170.0.0/24"
}

variable "apim_subnet_name" {
  description = "APIM subnet name"
  type        = string
  default     = "snet-citadel-apim"
}

variable "apim_subnet_prefix" {
  description = "APIM subnet address prefix (for new VNet)"
  type        = string
  default     = "10.170.0.0/26"
}

variable "private_endpoint_subnet_name" {
  description = "Private endpoint subnet name"
  type        = string
  default     = "snet-citadel-pe"
}

variable "private_endpoint_subnet_prefix" {
  description = "Private endpoint subnet address prefix (for new VNet)"
  type        = string
  default     = "10.170.0.64/26"
}

variable "logic_app_subnet_name" {
  description = "Logic App / Function App subnet name"
  type        = string
  default     = "snet-citadel-functions"
}

variable "logic_app_subnet_prefix" {
  description = "Logic App subnet address prefix (for new VNet)"
  type        = string
  default     = "10.170.0.128/26"
}

variable "enable_agent_subnet" {
  type    = bool
  default = true
}
variable "agent_subnet_name" {
  type    = string
  default = "snet-agents"
}
variable "agent_subnet_prefix" {
  type    = string
  default = "10.170.0.192/26"
}

variable "apim_network_type" {
  description = "APIM network type: 'External', 'Internal', or 'None'"
  type        = string
  default     = "External"

  validation {
    condition     = contains(["External", "Internal", "None"], var.apim_network_type)
    error_message = "Must be External, Internal, or None."
  }
}

variable "apim_v2_use_private_endpoint" {
  description = "Enable private endpoint for APIM V2 SKUs"
  type        = bool
  default     = true
}

variable "apim_v2_public_network_access" {
  description = "Allow public access for APIM V2 SKUs"
  type        = bool
  default     = true
}

# DNS Configuration
variable "dns_zone_rg" {
  description = "Resource group containing existing Private DNS Zones"
  type        = string
  default     = ""
}

variable "dns_subscription_id" {
  description = "Subscription ID containing existing Private DNS Zones"
  type        = string
  default     = ""
}

variable "existing_private_dns_zones" {
  description = "Map of existing private DNS zone resource IDs"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# COMPUTE SKU & SIZING
# -----------------------------------------------------------------------------

variable "apim_sku" {
  description = <<-EOT
    APIM SKU: Developer, StandardV2, Premium, PremiumV2.

    REGION AVAILABILITY (important — v2 SKUs are NOT globally available):

      - Developer / Premium (classic):
          Globally available in virtually all Azure public regions.

      - StandardV2 / PremiumV2 (stv2 platform):
          Available in a limited subset of regions. 
          Authoritative list (check before deploy):
          https://learn.microsoft.com/azure/api-management/api-management-region-availability
          az apim list-skus --location <region>

    If you hit `SkuNotSupportedInRegion` at apply time, either:
      (a) pick a supported region for `location`, or
      (b) fall back to `Premium` (classic)
  EOT
  type        = string
  default     = "StandardV2"

  validation {
    condition     = contains(["Developer", "StandardV2", "Premium", "PremiumV2"], var.apim_sku)
    error_message = "Must be Developer, StandardV2, Premium, or PremiumV2."
  }
}

variable "apim_sku_units" {
  description = "Number of APIM scale units"
  type        = number
  default     = 1
}

variable "apim_publisher_email" {
  description = "APIM publisher email"
  type        = string
  default     = "admin@contoso.com"
}

variable "apim_publisher_name" {
  description = "APIM publisher name"
  type        = string
  default     = "AI Citadel Admin"
}

variable "cosmos_db_rus" {
  description = "Cosmos DB provisioned throughput (RU/s)"
  type        = number
  default     = 400
}

variable "eventhub_capacity_units" {
  description = "Event Hub capacity units"
  type        = number
  default     = 1
}

variable "eventhub_partition_count" {
  description = "Event Hub partition count"
  type        = number
  default     = 4
}

variable "eventhub_disaster_recovery_config" {
  description = <<-EOT
    Optional disaster recovery pairing for the Event Hub namespace (Bicep
    parity: `disasterRecoveryConfig`). Set to `null` to skip. When provided,
    pairs this namespace with a partner namespace under the given alias.
    The partner namespace must already exist and match SKU tier.
  EOT
  type = object({
    partner_namespace_id = string
    alias                = optional(string, "default")
  })
  default = null
}

variable "logic_app_sku_tier" {
  description = "Logic App (Standard) SKU tier"
  type        = string
  default     = "WorkflowStandard"
}

variable "logic_app_sku_size" {
  description = "Logic App (Standard) SKU size"
  type        = string
  default     = "WS1"
}

variable "language_service_sku" {
  description = "Azure Language Service SKU"
  type        = string
  default     = "S"
}

variable "content_safety_sku" {
  description = "Azure Content Safety SKU"
  type        = string
  default     = "S0"
}

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

variable "enable_api_center" {
  description = "Deploy API Center as AI Registry"
  type        = bool
  default     = true
}

variable "enable_pii_redaction" {
  description = "Enable PII detection and masking via Language Service"
  type        = bool
  default     = true
}

variable "enable_content_safety" {
  description = "Enable Azure AI Content Safety"
  type        = bool
  default     = true
}

variable "enable_redis_cache" {
  description = "Deploy Azure Managed Redis for semantic caching"
  type        = bool
  default     = false
}

variable "create_app_insights_dashboards" {
  description = "Create Application Insights dashboards"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LOG ANALYTICS STRATEGY
# -----------------------------------------------------------------------------

variable "use_existing_log_analytics" {
  description = "Use an existing Log Analytics workspace"
  type        = bool
  default     = false
}

variable "existing_log_analytics_id" {
  description = "Resource ID of existing Log Analytics workspace"
  type        = string
  default     = ""
}

variable "existing_log_analytics_subscription_id" {
  description = "Subscription ID of the BYO Log Analytics workspace when it lives in a different subscription than the deployment. Leave blank to default to var.subscription_id. Bicep parity: existingLogAnalyticsSubscriptionId."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# NETWORK ACCESS SETTINGS
# -----------------------------------------------------------------------------

variable "cosmos_db_public_access" {
  description = "Cosmos DB public network access: Enabled or Disabled"
  type        = string
  default     = "Disabled"
}

variable "eventhub_network_access" {
  description = "Event Hub public network access: Enabled or Disabled"
  type        = string
  default     = "Enabled"
}

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
  type    = bool
  default = true
}

variable "ai_foundry_instances" {
  description = "List of AI Foundry instances to deploy"
  type = list(object({
    name                 = optional(string, "")
    location             = string
    custom_subdomain     = optional(string, "")
    default_project_name = optional(string, "citadel-governance-project")
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
    name              = string
    publisher         = optional(string, "OpenAI")
    version           = string
    sku               = optional(string, "GlobalStandard")
    capacity          = optional(number, 100)
    ai_service_index  = optional(number, 0)
  }))
  default = [
    {
      name    = "gpt-4o"
      version = "2024-11-20"
    },
    {
      name     = "gpt-4o-mini"
      version  = "2024-07-18"
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
    auth_scheme  = string # managedIdentity, apiKey, token
    auth_type    = optional(string)  # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'
    auth_config  = optional(object({
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
    auth_scheme  = string # managedIdentity, apiKey, token
    auth_type    = optional(string)  # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'
    auth_config  = optional(object({
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
  description = "Microsoft.Cache/redisEnterprise SKU name."
  type        = string
  default     = "Balanced_B10"
}

variable "redis_sku_capacity" {
  description = "Cluster capacity (used only for Enterprise_*/EnterpriseFlash_* SKUs)."
  type        = number
  default     = 2
}

variable "redis_public_network_access" {
  description = "Enabled or Disabled for Redis public network access."
  type        = string
  default     = "Disabled"
}

variable "redis_minimum_tls_version" {
  type    = string
  default = "1.2"
}

# -----------------------------------------------------------------------------
# OPTIONAL APIM EXTRA APIs — Bicep parity (main.bicep feature flags)
# -----------------------------------------------------------------------------

variable "enable_ai_model_inference" {
  description = "Enable Azure AI Model Inference API in APIM."
  type        = bool
  default     = false
}

variable "enable_document_intelligence" {
  description = "Enable Document Intelligence APIs (legacy + v4) in APIM."
  type        = bool
  default     = false
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

variable "enable_azure_ai_search" {
  description = "Enable Azure AI Search Index API in APIM."
  type        = bool
  default     = false
}

variable "enable_openai_realtime" {
  description = "Enable OpenAI Realtime WebSocket API in APIM."
  type        = bool
  default     = false
}

variable "enable_unified_ai_api" {
  description = "Enable wildcard Unified AI API in APIM."
  type        = bool
  default     = false
}

variable "enable_ai_gateway_pii_redaction" {
  description = "Enable PII redaction inside the AI gateway (distinct from PII service deployment)."
  type        = bool
  default     = false
}

variable "is_mcp_sample_deployed" {
  description = "Deploy the sample MCP server (weather-api / weather-mcp / ms-learn-mcp)."
  type        = bool
  default     = false
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

variable "use_azure_monitor_private_link_scope" {
  description = "Create an Azure Monitor Private Link Scope (AMPLS) for private ingestion."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC BODY-BYTE OVERRIDES (Bicep parity: azureMonitorLogSettings / appInsightsLogSettings)
# -----------------------------------------------------------------------------

variable "azure_monitor_log_settings" {
  description = "Per-API Azure Monitor body-logging limits."
  type = object({
    enabled                    = optional(bool, true)
    log_request_body_bytes     = optional(number, 8192)
    log_response_body_bytes    = optional(number, 8192)
  })
  default = {}
}

variable "app_insights_log_settings" {
  description = "Per-API Application Insights body-logging limits."
  type = object({
    enabled                    = optional(bool, true)
    log_request_body_bytes     = optional(number, 8192)
    log_response_body_bytes    = optional(number, 8192)
    sampling_percentage        = optional(number, 100)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# FOUNDRY EMBEDDINGS MODEL (Bicep parity: primaryFoundryEmbeddingModelName)
# -----------------------------------------------------------------------------

variable "primary_foundry_embedding_model_name" {
  description = "Embeddings model used for semantic-cache embeddings backend."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# ENTRA / AUTH SECRETS (Bicep parity: entraClientSecret)
# -----------------------------------------------------------------------------

variable "entra_client_secret" {
  description = "Optional Entra app client secret to persist into Key Vault."
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# LOGIC APP CONTENT SHARE (Bicep parity: logicContentShareName)
# -----------------------------------------------------------------------------

variable "logic_content_share_name" {
  description = "Content share name used by the Logic App (WEBSITE_CONTENTSHARE)."
  type        = string
  default     = ""
}

variable "enable_logic_app_code_deploy" {
  description = "Publish Logic App workflow code (src/usage-ingestion-logicapp) during `terraform apply`. Requires az CLI with the `functionapp` extension."
  type        = bool
  default     = false
}

variable "logic_app_code_source_path" {
  description = "Absolute path to the Logic App Standard project folder. Defaults to the vendored accelerator under ai-hub-gateway-solution-accelerator-citadel-v1/src/usage-ingestion-logicapp."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# APIM LOGIC PLANE — Bicep parity (§19.12)
# -----------------------------------------------------------------------------

variable "configure_circuit_breaker" {
  description = "Enable per-backend circuit breaker rules."
  type        = bool
  default     = true
}

variable "enable_embeddings_backend" {
  description = "Register a Foundry embeddings backend for semantic caching."
  type        = bool
  default     = false
}

variable "enable_pii_anonymization" {
  description = "Create policy fragments for PII anonymization/deanonymization."
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
  type    = string
  default = ""
}

variable "jwt_app_registration_id" {
  type    = string
  default = ""
}

variable "pii_service_key" {
  description = "Language Service key. Only consumed when MI auth is disabled."
  type        = string
  sensitive   = true
  default     = "replace-with-language-service-key-if-needed"
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
  description = "Rotate the Entra ID client secret after this many days (default: 2 years)."
  type        = number
  default     = 730
}

variable "enable_api_center_onboarding" {
  description = "Register each gateway API in the API Center (requires enable_api_center=true)."
  type        = bool
  default     = false
}

variable "enable_foundry_apim_connection" {
  description = "Create a dedicated APIM subscription for Foundry → APIM connections + optional per-project connections."
  type        = bool
  default     = false
}

variable "embeddings_backend_url" {
  description = "Foundry embeddings deployment endpoint (consumed only when enable_embeddings_backend = true)."
  type        = string
  default     = ""
}
