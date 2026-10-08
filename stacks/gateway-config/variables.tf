variable "entra_auth" {
  description = <<-EOT
    Entra ID JWT validation on the gateway (security-handler fragment; APIs then
    don't require a subscription key).
      enabled         Validate Entra tokens.
      tenant_id / client_id / audience
                      null = taken from the gateway app of stacks/identity, found by
                      its deterministic name (needs Graph Application.Read.All).
      login_endpoint  Entra authority (sovereign clouds differ).
  EOT
  type = object({
    enabled        = optional(bool, false)
    tenant_id      = optional(string)
    client_id      = optional(string)
    audience       = optional(string)
    login_endpoint = optional(string, "https://login.microsoftonline.com/")
  })
  default  = {}
  nullable = false
}

variable "features" {
  description = "Model-agnostic gateway capabilities owned by this stack."
  type = object({
    pii_redaction         = optional(bool, true)
    pii_anonymization     = optional(bool, true)
    content_safety        = optional(bool, true)
    azure_ai_search       = optional(bool, false)
    document_intelligence = optional(bool, false)
    embeddings_backend    = optional(bool, false)
    mcp_sample            = optional(bool, false)
    api_center_onboarding = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "foundry_primary_account_name" {
  description = "Name of the primary Foundry account (PII and Content Safety endpoint). \"\" = the generated name of platform's first instance."
  type        = string
  default     = ""
  nullable    = false
}

variable "ai_search_instances" {
  description = "Existing AI Search endpoints registered as APIM backends (features.azure_ai_search)."
  type = list(object({
    name     = string
    endpoint = string
  }))
  default  = []
  nullable = false
}

variable "embeddings_backend_url" {
  description = "Foundry embeddings deployment endpoint for the semantic cache (features.embeddings_backend)."
  type        = string
  default     = ""
  nullable    = false
}

variable "ms_learn_mcp_backend_url" {
  description = "Backend URL of the Microsoft Learn MCP server (features.mcp_sample)."
  type        = string
  default     = "https://learn.microsoft.com/api/mcp"
}

variable "api_diagnostics" {
  description = "Application Insights and Azure Monitor diagnostics on the service APIs (AI Search, Document Intelligence): enabled, headers and body bytes logged."
  type = object({
    enabled    = optional(bool, false)
    headers    = optional(list(string), ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"])
    body_bytes = optional(number, 0)
  })
  default  = {}
  nullable = false
}
