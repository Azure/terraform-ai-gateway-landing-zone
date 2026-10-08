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

variable "adopt_existing_resources" {
  description = "Set true for the run that upgrades an environment deployed before Phase 2: resources that moved to azapi-based Azure Verified Modules are imported (adopt.tf) instead of created. Leave false for new environments. See docs/operations/adopting-existing-resources.md."
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

variable "apim_service_name" {
  description = "DEPRECATED: use apim.name. API Management service name. Leave empty for auto-generated."
  type        = string
  default     = null
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
  description = "DEPRECATED: use network.mode. Use an existing VNet instead of creating a new one"
  type        = bool
  default     = null
}

variable "existing_vnet_rg" {
  description = "DEPRECATED: use network.resource_group_name. Resource group of the existing VNet (required if use_existing_vnet = true)"
  type        = string
  default     = null
}

variable "vnet_name" {
  description = "DEPRECATED: use network.vnet_name. VNet name (existing or new)"
  type        = string
  default     = null
}

variable "vnet_address_prefix" {
  description = "DEPRECATED: use network.address_space. Address prefix for new VNet"
  type        = string
  default     = null
}

variable "apim_subnet_name" {
  description = "DEPRECATED: use network.subnets.apim.name. APIM subnet name"
  type        = string
  default     = null
}

variable "apim_subnet_prefix" {
  description = "DEPRECATED: use network.subnets.apim.prefix. APIM subnet address prefix (for new VNet)"
  type        = string
  default     = null
}

variable "private_endpoint_subnet_name" {
  description = "DEPRECATED: use network.subnets.private_endpoint.name. Private endpoint subnet name"
  type        = string
  default     = null
}

variable "private_endpoint_subnet_prefix" {
  description = "DEPRECATED: use network.subnets.private_endpoint.prefix. Private endpoint subnet address prefix (for new VNet)"
  type        = string
  default     = null
}

variable "logic_app_subnet_name" {
  description = "DEPRECATED: use network.subnets.logic_app.name. Logic App / Function App subnet name"
  type        = string
  default     = null
}

variable "logic_app_subnet_prefix" {
  description = "DEPRECATED: use network.subnets.logic_app.prefix. Logic App subnet address prefix (for new VNet)"
  type        = string
  default     = null
}

variable "enable_agent_subnet" {
  description = "DEPRECATED: use network.subnets.agent.enabled. Create a dedicated subnet for Foundry Agent Service network injection."
  type        = bool
  default     = null
}
variable "agent_subnet_name" {
  description = "DEPRECATED: use network.subnets.agent.name. Name of the Foundry agent subnet."
  type        = string
  default     = null
}
variable "agent_subnet_prefix" {
  description = "DEPRECATED: use network.subnets.agent.prefix. Address prefix (CIDR) of the Foundry agent subnet."
  type        = string
  default     = null
}

variable "apim_network_type" {
  description = "DEPRECATED: use apim.vnet_mode. APIM network type: 'External', 'Internal', or 'None'"
  type        = string
  default     = null

  validation {
    condition     = contains(["External", "Internal", "None"], coalesce(var.apim_network_type, "External"))
    error_message = "Must be External, Internal, or None."
  }
}

variable "apim_v2_use_private_endpoint" {
  description = "DEPRECATED: use apim.private_endpoint. Enable private endpoint for APIM V2 SKUs"
  type        = bool
  default     = null
}

variable "apim_v2_public_network_access" {
  description = "DEPRECATED: use apim.public_network_access. Allow public access for APIM V2 SKUs"
  type        = bool
  default     = null
}

# DNS Configuration
variable "dns_zone_rg" {
  description = "DEPRECATED: use network.private_dns.resource_group_name. Resource group containing existing Private DNS Zones"
  type        = string
  default     = null
}

variable "existing_private_dns_zones" {
  description = "DEPRECATED: use network.private_dns.zone_ids. Map of existing private DNS zone resource IDs"
  type        = map(string)
  default     = null
}

# -----------------------------------------------------------------------------
# COMPUTE SKU & SIZING
# -----------------------------------------------------------------------------

variable "apim_sku" {
  description = <<-EOT
    DEPRECATED: use apim.sku.
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
  default     = null

  validation {
    condition     = contains(["Developer", "StandardV2", "Premium", "PremiumV2"], coalesce(var.apim_sku, "StandardV2"))
    error_message = "Must be Developer, StandardV2, Premium, or PremiumV2."
  }
}

variable "apim_sku_units" {
  description = "DEPRECATED: use apim.capacity. Number of APIM scale units"
  type        = number
  default     = null
}

variable "apim_publisher_email" {
  description = "DEPRECATED: use apim.publisher_email. APIM publisher email"
  type        = string
  default     = null
}

variable "apim_publisher_name" {
  description = "DEPRECATED: use apim.publisher_name. APIM publisher name"
  type        = string
  default     = null
}

variable "eventhub_capacity_units" {
  description = "DEPRECATED: use usage_pipeline.eventhub.capacity. Event Hub capacity units"
  type        = number
  default     = null
}

variable "eventhub_disaster_recovery_config" {
  description = <<-EOT
    DEPRECATED: use usage_pipeline.eventhub.disaster_recovery.
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

variable "logic_app_sku_size" {
  description = "DEPRECATED: use usage_pipeline.logic_app.sku. Logic App (Standard) SKU size. Used only when logic_app_hosting_model = \"WorkflowStandard\"."
  type        = string
  default     = null
}

variable "logic_app_hosting_model" {
  description = <<-EOT
    DEPRECATED: use usage_pipeline.logic_app.hosting.
    Hosting option for the usage-ingestion Logic App (Standard):

      - "WorkflowStandard"        (default) Workflow Service Plan (WS1/WS2/WS3) with
                                  regional VNet integration. The runtime needs an
                                  Azure Files content share, so the storage account
                                  MUST keep shared-key access enabled.
      - "AppServiceEnvironmentV3" Isolated v2 plan inside a dedicated App Service
                                  Environment v3. Runtime storage uses the usage UAMI
                                  (AzureWebJobsStorage__* settings), no content share
                                  is needed, and shared-key access on the storage
                                  account is disabled.

    See https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account
  EOT
  type        = string
  default     = null

  validation {
    condition     = contains(["WorkflowStandard", "AppServiceEnvironmentV3"], coalesce(var.logic_app_hosting_model, "WorkflowStandard"))
    error_message = "logic_app_hosting_model must be WorkflowStandard or AppServiceEnvironmentV3."
  }
}

variable "logic_app_ase_sku_size" {
  description = "DEPRECATED: use usage_pipeline.logic_app.sku. Isolated v2 App Service plan SKU for the Logic App when logic_app_hosting_model = \"AppServiceEnvironmentV3\"."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^I[1-6]m?v2$", coalesce(var.logic_app_ase_sku_size, "I1v2")))
    error_message = "logic_app_ase_sku_size must be an Isolated v2 SKU (I1v2..I6v2 or I1mv2..I5mv2)."
  }
}

variable "logic_app_ase_worker_count" {
  description = "DEPRECATED: use usage_pipeline.logic_app.worker_count. Number of Isolated v2 instances for the Logic App plan inside the ASE v3."
  type        = number
  default     = null
}

variable "ase_subnet_name" {
  description = "DEPRECATED: use network.subnets.ase.name. Subnet for the App Service Environment v3 (only used when logic_app_hosting_model = \"AppServiceEnvironmentV3\"). Must be empty and delegated to Microsoft.Web/hostingEnvironments when using an existing VNet."
  type        = string
  default     = null
}

variable "ase_subnet_prefix" {
  description = <<-EOT
    DEPRECATED: use network.subnets.ase.prefix.
    Address prefix for the ASE v3 subnet (new VNet only). Minimum /27; Microsoft
    recommends /24 for production scale. If this range is not inside
    vnet_address_prefix it is added to the VNet as an extra address space.
  EOT
  type        = string
  default     = null
}

variable "ase_internal_load_balancing_mode" {
  description = "DEPRECATED: use usage_pipeline.ase.internal_load_balancing_mode. ASE v3 ingress: \"Web, Publishing\" (internal/ILB — app and SCM endpoints reachable only from the VNet) or \"None\" (external, public VIP)."
  type        = string
  default     = null

  validation {
    condition     = contains(["None", "Web, Publishing"], coalesce(var.ase_internal_load_balancing_mode, "Web, Publishing"))
    error_message = "ase_internal_load_balancing_mode must be \"None\" or \"Web, Publishing\"."
  }
}

variable "ase_zone_redundant" {
  description = "DEPRECATED: use usage_pipeline.ase.zone_redundant. Deploy the ASE v3 as zone redundant (region must support availability zones; increases minimum billed instances)."
  type        = bool
  default     = null
}

variable "ase_create_private_dns_zone" {
  description = "DEPRECATED: use usage_pipeline.ase.create_private_dns_zone. For an internal (ILB) ASE v3, create the <ase>.appserviceenvironment.net private DNS zone (*, *.scm, @ records) and link it to the VNet. Set false when DNS is managed centrally (hub)."
  type        = bool
  default     = null
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
  description = "DEPRECATED: use features.api_center. Deploy API Center as AI Registry"
  type        = bool
  default     = null
}

variable "enable_pii_redaction" {
  description = "DEPRECATED: use features.pii_redaction. Enable PII detection and masking via Language Service"
  type        = bool
  default     = null
}

variable "enable_content_safety" {
  description = "DEPRECATED: use features.content_safety. Enable Azure AI Content Safety"
  type        = bool
  default     = null
}

variable "enable_redis_cache" {
  description = "DEPRECATED: use features.semantic_cache. Deploy Azure Managed Redis for semantic caching"
  type        = bool
  default     = null
}

variable "create_app_insights_dashboards" {
  description = "DEPRECATED: use monitoring.app_insights_dashboards. Create Application Insights dashboards"
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# LOG ANALYTICS STRATEGY
# -----------------------------------------------------------------------------

variable "use_existing_log_analytics" {
  description = "DEPRECATED: use monitoring.log_analytics_workspace_id. Use an existing Log Analytics workspace"
  type        = bool
  default     = null
}

variable "existing_log_analytics_id" {
  description = "DEPRECATED: use monitoring.log_analytics_workspace_id. Resource ID of existing Log Analytics workspace"
  type        = string
  default     = null
}

variable "existing_log_analytics_subscription_id" {
  description = "DEPRECATED: use monitoring.log_analytics_subscription_id. Subscription ID of the BYO Log Analytics workspace when it lives in a different subscription than the deployment. Leave blank to default to var.subscription_id. Bicep parity: existingLogAnalyticsSubscriptionId."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# NETWORK ACCESS SETTINGS
# -----------------------------------------------------------------------------

variable "cosmos_db_public_access" {
  description = "DEPRECATED: use usage_pipeline.cosmos.public_network_access. Cosmos DB public network access: Enabled or Disabled"
  type        = string
  default     = null
}

variable "cosmos_db_local_auth_enabled" {
  description = <<-EOT
    DEPRECATED: use usage_pipeline.cosmos.local_auth_enabled.
    Allow key / connection-string authentication on Cosmos DB. Default false:
    the Logic App connects with its managed identity (Cosmos Built-in Data
    Contributor), so no account key is needed. Set true only if an external
    client (e.g. a Power BI report refreshed with the account key) still
    depends on keys.
  EOT
  type        = bool
  default     = null
}

variable "eventhub_network_access" {
  description = "DEPRECATED: use usage_pipeline.eventhub.public_network_access. Event Hub public network access: Enabled or Disabled"
  type        = string
  default     = null
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

variable "enable_ai_model_inference" {
  description = "DEPRECATED: use features.ai_model_inference. Enable Azure AI Model Inference API in APIM."
  type        = bool
  default     = null
}

variable "enable_document_intelligence" {
  description = "DEPRECATED: use features.document_intelligence. Enable Document Intelligence APIs (legacy + v4) in APIM."
  type        = bool
  default     = null
}

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

variable "enable_azure_ai_search" {
  description = "DEPRECATED: use features.azure_ai_search. Enable Azure AI Search Index API in APIM."
  type        = bool
  default     = null
}

variable "enable_openai_realtime" {
  description = "DEPRECATED: use features.openai_realtime. Enable OpenAI Realtime WebSocket API in APIM."
  type        = bool
  default     = null
}

variable "enable_unified_ai_api" {
  description = "DEPRECATED: use features.unified_ai_api. Enable wildcard Unified AI API in APIM."
  type        = bool
  default     = null
}

variable "is_mcp_sample_deployed" {
  description = "DEPRECATED: use features.mcp_sample. Deploy the sample MCP server (weather-api / weather-mcp / ms-learn-mcp)."
  type        = bool
  default     = null
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
  description = "DEPRECATED: use monitoring.private_link_scope. Create an Azure Monitor Private Link Scope (AMPLS) for private ingestion."
  type        = bool
  default     = null
}

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

variable "logic_content_share_name" {
  description = "DEPRECATED: use usage_pipeline.logic_app.content_share_name. Content share name used by the Logic App (WEBSITE_CONTENTSHARE). Ignored when logic_app_hosting_model = \"AppServiceEnvironmentV3\"."
  type        = string
  default     = null
}

variable "enable_logic_app_code_deploy" {
  description = "DEPRECATED: use usage_pipeline.logic_app.code_deploy. Publish Logic App workflow code (src/usage-ingestion-logicapp) during `terraform apply`. Requires az CLI with the `functionapp` extension."
  type        = bool
  default     = null
}

variable "logic_app_code_source_path" {
  description = "DEPRECATED: use usage_pipeline.logic_app.code_source_path. Absolute path to the Logic App Standard project folder. Defaults to the vendored accelerator under ai-hub-gateway-solution-accelerator-citadel-v1/src/usage-ingestion-logicapp."
  type        = string
  default     = null
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
  description = "DEPRECATED: use features.embeddings_backend. Register a Foundry embeddings backend for semantic caching."
  type        = bool
  default     = null
}

variable "enable_pii_anonymization" {
  description = "DEPRECATED: use features.pii_anonymization. Create policy fragments for PII anonymization/deanonymization."
  type        = bool
  default     = null
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

variable "enable_api_center_onboarding" {
  description = "DEPRECATED: use features.api_center_onboarding. Register each gateway API in the API Center (requires enable_api_center=true)."
  type        = bool
  default     = null
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


# =============================================================================
# DEPRECATED INPUTS
#
# These variables were accepted but never reached a resource (review finding C2:
# "user input is silently dropped"). They stay declared so existing tfvars files
# keep working, default to null, and the check below warns when one is set.
# They will be removed in the next major release.
# =============================================================================

variable "cosmos_db_rus" {
  description = "DEPRECATED, ignored. Cosmos DB is deployed serverless (EnableServerless); provisioned RU/s don't apply."
  type        = number
  default     = null
}

variable "eventhub_partition_count" {
  description = "DEPRECATED, ignored. Partition counts are fixed (ai-usage 4, pii-usage 2); changing them recreates the hubs. Becomes configurable through the typed usage_pipeline input."
  type        = number
  default     = null
}

variable "logic_app_sku_tier" {
  description = "DEPRECATED, ignored. The plan tier is derived from logic_app_sku_size / logic_app_hosting_option."
  type        = string
  default     = null
}

variable "dns_subscription_id" {
  description = "DEPRECATED, ignored. Cross-subscription private DNS lookup isn't implemented; pass zone IDs through existing_private_dns_zones instead."
  type        = string
  default     = null
}

variable "primary_foundry_embedding_model_name" {
  description = "DEPRECATED, ignored. Use embeddings_backend_url / enable_embeddings_backend."
  type        = string
  default     = null
}

variable "language_service_sku" {
  description = "DEPRECATED, ignored. No Language resource is deployed; PII uses the Foundry endpoint."
  type        = string
  default     = null
}

variable "content_safety_sku" {
  description = "DEPRECATED, ignored. No Content Safety resource is deployed; content safety uses the Foundry endpoint."
  type        = string
  default     = null
}

variable "enable_ai_gateway_pii_redaction" {
  description = "DEPRECATED, ignored. PII redaction is controlled by enable_pii_redaction."
  type        = bool
  default     = null
}

variable "entra_client_secret" {
  description = "DEPRECATED, ignored. No client secret is persisted from input; the Entra module manages its own secret rotation."
  type        = string
  default     = null
  sensitive   = true
}

variable "azure_monitor_log_settings" {
  description = "DEPRECATED, ignored. API diagnostics use extra_api_log_settings."
  type = object({
    enabled                 = optional(bool, true)
    log_request_body_bytes  = optional(number, 8192)
    log_response_body_bytes = optional(number, 8192)
  })
  default = null
}

variable "app_insights_log_settings" {
  description = "DEPRECATED, ignored. API diagnostics use extra_api_log_settings."
  type = object({
    enabled                 = optional(bool, true)
    log_request_body_bytes  = optional(number, 8192)
    log_response_body_bytes = optional(number, 8192)
    sampling_percentage     = optional(number, 100)
  })
  default = null
}

variable "nsg_on_all_subnets" {
  description = "DEPRECATED, ignored. Every greenfield subnet now has an NSG (WP-2.6, ALZ Deny-Subnet-Without-Nsg)."
  type        = bool
  default     = null
}
