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

variable "pii_service" {
  description = <<-EOT
    Where PII redaction and anonymization (features.pii_redaction) call the Language API.
      source  foundry    the primary Foundry account of stacks/platform (an AIServices account
                         serves Language too); the default.
              dedicated  the standalone Language account of stacks/platform
                         (language_service.enabled), found by name.
              url        an existing Language / AIServices endpoint you give in url
                         (the APIM identity needs Cognitive Services User on it).
      url     Endpoint when source = url, e.g. https://<name>.cognitiveservices.azure.com/.
  EOT
  type = object({
    source = optional(string, "foundry")
    url    = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["foundry", "dedicated", "url"], var.pii_service.source)
    error_message = "pii_service.source must be foundry, dedicated or url."
  }
  validation {
    condition     = var.pii_service.source != "url" || (var.pii_service.url != null && var.pii_service.url != "")
    error_message = "pii_service.url is required when pii_service.source = url."
  }
}

variable "content_safety_service" {
  description = <<-EOT
    Where the content-safety backend and named value (features.content_safety) point.
      source  foundry    the primary Foundry account of stacks/platform (an AIServices account
                         serves Content Safety too); the default.
              dedicated  the standalone Content Safety account of stacks/platform
                         (content_safety_service.enabled), found by name.
              url        an existing Content Safety / AIServices endpoint you give in url.
      url     Endpoint when source = url.
  EOT
  type = object({
    source = optional(string, "foundry")
    url    = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["foundry", "dedicated", "url"], var.content_safety_service.source)
    error_message = "content_safety_service.source must be foundry, dedicated or url."
  }
  validation {
    condition     = var.content_safety_service.source != "url" || (var.content_safety_service.url != null && var.content_safety_service.url != "")
    error_message = "content_safety_service.url is required when content_safety_service.source = url."
  }
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
