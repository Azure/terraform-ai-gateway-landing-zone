variable "resource_group_name" {
  description = "Name of the resource group the module deploys into."
  type        = string
}
variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}
variable "apim_name" {
  description = "Name of the API Management service."
  type        = string
}
variable "sku_name" {
  description = "APIM SKU: Developer, StandardV2, Premium, PremiumV2. REGION AVAILABILITY (important — v2 SKUs are NOT globally available): - Developer / Premium (classic): Globally available in virtually all Azure public regions. - StandardV2 / PremiumV2 (stv2 platform): Available in a limited subset of regions. Authoritative list (check before deploy): https://learn.microsoft.com/azure/api-management/api-management-region-availability az apim list-skus --location <region> If you hit `SkuNotSupportedInRegion` at apply time, either: (a) pick a supported region for `location`, or (b) fall back to `Premium` (classic)"
  type        = string
}
variable "sku_capacity" {
  description = "Number of APIM scale units"
  type        = number
}
variable "publisher_email" {
  description = "APIM publisher email"
  type        = string
}
variable "publisher_name" {
  description = "APIM publisher name"
  type        = string
}
variable "apim_network_type" {
  description = "APIM network type: 'External', 'Internal', or 'None'"
  type        = string
}
variable "is_apim_v2" {
  description = "True when the APIM SKU is a v2 SKU (BasicV2, StandardV2 or PremiumV2)."
  type        = bool
}
variable "apim_subnet_id" {
  description = "Resource ID of the APIM subnet (VNet injection or outbound integration)."
  type        = string
}
variable "pe_subnet_id" {
  description = "Resource ID of the subnet that hosts private endpoints."
  type        = string
}
variable "vnet_id" {
  description = "Resource ID of the virtual network."
  type        = string
}
variable "apim_v2_use_private_endpoint" {
  description = "Enable private endpoint for APIM V2 SKUs"
  type        = bool
}
variable "apim_v2_public_network_access" {
  description = "Allow public access for APIM V2 SKUs"
  type        = bool
}
variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity the service runs as."
  type        = string
}
variable "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity the service runs as."
  type        = string
}

variable "eventhub_endpoint_uri" {
  type        = string
  description = "EventHub namespace endpoint URI (https://<ns>.servicebus.windows.net)"
}
variable "eventhub_usage_hub_name" {
  type        = string
  description = "Name of the APIM usage event hub inside the namespace (matches Bicep output eventHub.name)."
  default     = "ai-usage"
}
variable "eventhub_pii_hub_name" {
  type        = string
  description = "Name of the PII usage event hub (matches Bicep output eventHubPIIName)."
  default     = "pii-usage"
}
variable "pii_service_endpoint" {
  description = "Endpoint of the PII detection service (Foundry Language); empty when PII redaction is off."
  type        = string
}
variable "content_safety_endpoint" {
  description = "Endpoint of the content-safety service (Foundry); empty when content safety is off."
  type        = string
}
variable "enable_pii_redaction" {
  description = "Enable PII detection and masking via Language Service"
  type        = bool
}
variable "enable_content_safety" {
  description = "Enable Azure AI Content Safety"
  type        = bool
}
variable "entra_auth_enabled" {
  description = "Enable Entra ID JWT validation on APIM"
  type        = bool
}
variable "entra_tenant_id" {
  description = "Entra ID tenant ID for JWT validation"
  type        = string
}
variable "entra_client_id" {
  description = "Entra ID client ID (application ID)"
  type        = string
}
variable "entra_audience" {
  description = "Entra ID audience (resource identifier)"
  type        = string
}
variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace that receives diagnostic settings."
  type        = string
}
variable "log_verbosity" {
  description = "APIM diagnostic log verbosity: verbose, information, error"
  type        = string
}
variable "log_body_bytes" {
  description = "Max bytes to log from request/response body"
  type        = number
}
variable "dns_zone_id_apim" {
  description = "Resource ID of the privatelink.azure-api.net DNS zone for the gateway private endpoint (empty = none)."
  type        = string
}

variable "create_internal_dns" {
  description = "For apim_network_type = Internal (Developer/Premium), create per-hostname private DNS zones for the gateway/portal/developer/management/scm endpoints and link them to the VNet."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# APIM hardening
# -----------------------------------------------------------------------------
variable "app_insights_id" {
  description = "Resource ID of the Application Insights component used by the APIM logger."
  type        = string
}
variable "app_insights_instrumentation_key" {
  description = "Instrumentation key of the APIM Application Insights component (legacy logger credential)."
  type        = string
  sensitive   = true
}
variable "app_insights_connection_string" {
  description = "Application Insights connection string — used in the AppInsights logger (Bicep parity)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_cache_connection_string" {
  description = "Optional Azure Managed Redis connection string. When set, creates an APIM service/caches resource."
  type        = string
  sensitive   = true
  default     = ""
}

variable "apim_zones" {
  description = "Availability zones for APIM (Premium only, skuCount>1). Computed at root; pass explicitly here."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# APIM logic plane (Bicep parity: llm-backends, policy fragments, extra APIs)
# -----------------------------------------------------------------------------

variable "llm_backend_config" {
  description = "Bicep llmBackendConfig — one entry per LLM endpoint."
  type = list(object({
    backend_id   = string
    backend_type = string
    endpoint     = string
    auth_scheme  = optional(string) # legacy, retained
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

variable "configure_circuit_breaker" {
  description = "Enable per-backend circuit breaker rules."
  type        = bool
  default     = true
}

variable "ai_search_instances" {
  description = "Existing AI Search endpoints to register as APIM backends."
  type = list(object({
    name        = string
    description = optional(string, "AI Search backend")
    url         = string
  }))
  default = []
}

variable "enable_azure_ai_search" {
  description = "Enable Azure AI Search Index API in APIM."
  type        = bool
  default     = false
}

variable "enable_embeddings_backend" {
  description = "Register a Foundry embeddings backend for semantic caching."
  type        = bool
  default     = false
}

variable "embeddings_backend_id" {
  description = "APIM backend ID of the embeddings backend used by semantic caching."
  type        = string
  default     = "foundry-embeddings"
}

variable "embeddings_backend_url" {
  description = "Foundry embeddings deployment endpoint (consumed only when enable_embeddings_backend = true)."
  type        = string
  default     = ""
}

variable "enable_pii_anonymization" {
  description = "Feature flag for policy fragments that implement PII redaction."
  type        = bool
  default     = true
}

variable "enable_unified_ai_api" {
  description = "Enable wildcard Unified AI API in APIM."
  type        = bool
  default     = false
}

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

# Bicep parity: apim.bicep inferenceAPIType (default 'OpenAIV1'). Drives the
# Universal LLM API OpenAPI spec + base path selection.
variable "inference_api_type" {
  description = "Universal LLM API inference contract (Bicep: inferenceAPIType). One of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  type        = string
  default     = "OpenAIV1"
  validation {
    condition     = contains(["AzureOpenAI", "AzureAI", "OpenAI", "OpenAIV1"], var.inference_api_type)
    error_message = "inference_api_type must be one of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  }
}

variable "enable_openai_realtime" {
  description = "Enable OpenAI Realtime WebSocket API in APIM."
  type        = bool
  default     = false
}

variable "is_mcp_sample_deployed" {
  description = "Deploy the sample MCP server (weather-api / weather-mcp / ms-learn-mcp)."
  type        = bool
  default     = false
}

variable "ms_learn_mcp_backend_url" {
  description = "Backend URL for the MS Learn MCP server."
  type        = string
  default     = "https://learn.microsoft.com/api/mcp"
}

# -----------------------------------------------------------------------------
# Extra-API diagnostics (Bicep parity: api.bicep `enableAPIDiagnostics`).
# Bicep callers in apim.bicep pass `false` for AI Search, Doc Intel, OpenAI
# Realtime, so the default here is also false. When set to true, both
# `applicationinsights` and `azuremonitor` per-API diagnostics are created
# matching the api.bicep resource shape (azuremonitor includes the LLM logs
# block via azapi).
# -----------------------------------------------------------------------------

variable "enable_extra_api_diagnostics" {
  description = "Attach API-level diagnostics to the extra service APIs (AI Search, Document Intelligence, ...)."
  type        = bool
  default     = false
}

variable "extra_api_log_settings" {
  description = "Bicep parity: api.bicep `logSettings` (headers + body bytes for app insights)."
  type = object({
    headers = list(string)
    body    = object({ bytes = number })
  })
  default = {
    headers = ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"]
    body    = { bytes = 0 }
  }
}

variable "enable_jwt_auth" {
  description = "When true, JWT-* named values are populated from jwt_tenant_id / jwt_app_registration_id."
  type        = bool
  default     = false
}

variable "jwt_tenant_id" {
  description = "Entra tenant ID used by the JWT-validation policies."
  type        = string
  default     = ""
}

variable "jwt_app_registration_id" {
  description = "Entra application (client) ID used as the JWT audience."
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "Subscription ID of the deployment."
  type        = string
}

variable "azure_login_endpoint" {
  description = "Entra login endpoint (e.g. https://login.microsoftonline.com/)."
  type        = string
  default     = "https://login.microsoftonline.com/"
}

# API Center onboarding (Bicep parity)
variable "enable_api_center_onboarding" {
  description = "Register each gateway API in API Center (needs an API Center service)."
  type        = bool
  default     = false
}

variable "api_center_service_name" {
  description = "Name of the API Center service that receives the API registrations."
  type        = string
  default     = ""
}

variable "api_center_workspace_name" {
  description = "API Center workspace that receives the API registrations."
  type        = string
  default     = "default"
}

variable "api_center_environment_name" {
  description = "API Center environment for REST APIs."
  type        = string
  default     = "api-dev"
}

variable "api_center_mcp_environment_name" {
  description = "API Center environment for MCP servers."
  type        = string
  default     = "mcp-dev"
}

# Foundry → APIM named subscription
variable "enable_foundry_apim_connection" {
  description = "Create a dedicated APIM subscription for Foundry connections."
  type        = bool
  default     = false
}

variable "model_aliases" {
  description = "Model alias definitions. Each: { name, models[], strategy?, weights?[] }"
  type = list(object({
    name     = string
    models   = list(string)
    strategy = optional(string, "priority")
    weights  = optional(list(number), [])
  }))
  default = []
}

variable "aws_region" {
  description = "AWS region for AWS Bedrock backends (APIM named value)."
  type        = string
  default     = ""
}


variable "enable_redis_cache" {
  description = "Attach Azure Managed Redis as the APIM external cache (requires redis_cache_connection_string)."
  type        = bool
  default     = false
}
