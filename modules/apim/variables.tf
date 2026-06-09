variable "resource_group_name"           { type = string }
variable "location"                        { type = string }
variable "tags"                            { type = map(string) }
variable "apim_name"                       { type = string }
variable "sku_name"                        { type = string }
variable "sku_capacity"                    { type = number }
variable "publisher_email"                 { type = string }
variable "publisher_name"                  { type = string }
variable "apim_network_type"               { type = string }
variable "is_apim_v2"                      { type = bool }
variable "apim_subnet_id"                  { type = string }
variable "pe_subnet_id"                    { type = string }
variable "vnet_id"                         { type = string }
variable "apim_v2_use_private_endpoint"    { type = bool }
variable "apim_v2_public_network_access"   { type = bool }
variable "managed_identity_id"             { type = string }
variable "managed_identity_client_id"      { type = string }

variable "eventhub_namespace_name"         { type = string }
variable "eventhub_endpoint_uri"           {
    type = string
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
variable "cosmos_db_endpoint"              { type = string }
variable "pii_service_endpoint"            { type = string }
variable "content_safety_endpoint"         { type = string }
variable "enable_pii_redaction"             { type = bool }
variable "enable_content_safety"            { type = bool }
variable "entra_auth_enabled"              { type = bool }
variable "entra_tenant_id"                 { type = string }
variable "entra_client_id"                 { type = string }
variable "entra_audience"                  { type = string }
variable "log_analytics_id"               { type = string }
variable "log_verbosity"                   { type = string }
variable "log_body_bytes"                  { type = number }
variable "dns_zone_id_apim"               { type = string }

# -----------------------------------------------------------------------------
# APIM hardening
# -----------------------------------------------------------------------------
variable "app_insights_id"                 { type = string }
variable "app_insights_instrumentation_key" { 
    type = string
    sensitive = true
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
    auth_scheme  = optional(string)  # legacy, retained
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

variable "configure_circuit_breaker" {
  type    = bool
  default = true
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
  type    = bool
  default = false
}

variable "enable_embeddings_backend" {
  type    = bool
  default = false
}

variable "embeddings_backend_id" {
  type    = string
  default = "foundry-embeddings"
}

variable "embeddings_backend_url" {
  type    = string
  default = ""
}

variable "enable_pii_anonymization" {
  description = "Feature flag for policy fragments that implement PII redaction."
  type        = bool
  default     = true
}

variable "enable_unified_ai_api" {
  type    = bool
  default = false
}

variable "enable_ai_model_inference" {
  type    = bool
  default = false
}

variable "enable_document_intelligence" {
  type    = bool
  default = false
}

# Bicep parity: apim.bicep inferenceAPIType (default 'OpenAIV1'). Drives the
# Universal LLM API OpenAPI spec + base path selection.
variable "inference_api_type" {
  type    = string
  default = "OpenAIV1"
  validation {
    condition     = contains(["AzureOpenAI", "AzureAI", "OpenAI", "OpenAIV1"], var.inference_api_type)
    error_message = "inference_api_type must be one of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  }
}

variable "enable_openai_realtime" {
  type    = bool
  default = false
}

variable "is_mcp_sample_deployed" {
  type    = bool
  default = false
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
  type    = bool
  default = false
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
  type    = string
  default = ""
}

variable "jwt_app_registration_id" {
  type    = string
  default = ""
}

variable "pii_service_key" {
  description = "Language Service key — only used when MI auth is not available."
  type        = string
  sensitive   = true
  default     = "replace-with-language-service-key-if-needed"
}

variable "subscription_id" {
  type    = string
}

variable "azure_login_endpoint" {
  description = "Entra login endpoint (e.g. https://login.microsoftonline.com/)."
  type        = string
  default     = "https://login.microsoftonline.com/"
}

# API Center onboarding (Bicep parity)
variable "enable_api_center_onboarding" {
  type    = bool
  default = false
}

variable "api_center_service_name" {
  type    = string
  default = ""
}

variable "api_center_workspace_name" {
  type    = string
  default = "default"
}

variable "api_center_environment_name" {
  type    = string
  default = "api-dev"
}

variable "api_center_mcp_environment_name" {
  type    = string
  default = "mcp-dev"
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

variable "aws_access_key" { 
  type = string
  sensitive = true
  default = ""
}
variable "aws_secret_key" { 
  type = string
  sensitive = true
  default = ""
}
variable "aws_region" { 
  type = string
  default = ""
}
variable "key_vault_name" { 
  type = string
  default = ""
}