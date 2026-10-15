variable "entra_auth" {
  description = <<-EOT
    Entra ID as the gateway's JWT identity provider: fills the JWT-OpenIdConfigUrl, JWT-Issuer and
    JWT-AppRegistrationId named values the security-handler fragment validates tokens against. An
    access contract then opts in per service (jwt_required, optionally required_roles); the
    subscription key stays required on every API, a token is never a replacement for it.
      enabled         Configure the named values (false: "not-configured" placeholders, and a contract
                      that requires a JWT without its own jwt_* overrides gets 503).
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

variable "semantic_cache" {
  description = <<-EOT
    Semantic cache for the LLM APIs (llm-semantic-cache-lookup / -store in Azure Managed Redis).
    Needs stacks/platform features.semantic_cache (Redis as the APIM external cache, APIM's
    system-assigned identity) and an embeddings deployment. Access contracts opt in per service
    (services[*].semantic_cache); other products never use the cache.
      enabled                 Create the embeddings backend (embeddings-backend) and the active
                              semantic-cache-lookup / semantic-cache-store fragments. false: the
                              fragments do nothing (the LLM API policies always include them).
      embeddings_deployment   Embeddings deployment name on the primary Foundry account.
      embeddings_url          Full embeddings endpoint instead (no query string), e.g.
                              https://<account>.openai.azure.com/openai/deployments/<name>/embeddings.
                              APIM's system-assigned identity needs Cognitive Services OpenAI User on it.
      score_threshold         0.0-1.0; lower = a closer match is needed. Above 0.2 risks mismatches.
      ttl_seconds             How long a response is cached. Gateway-wide: the store must sit in the
                              LLM API policies with the lookup, and APIM accepts only a literal here.
      ignore_system_messages  Leave system messages out of the similarity.
      max_message_count       Skip caching for conversations longer than this many messages.
    Only non-streaming chat completions are cached, partitioned by subscription and model.
  EOT
  type = object({
    enabled                = optional(bool, false)
    embeddings_deployment  = optional(string, "text-embedding-3-small")
    embeddings_url         = optional(string)
    score_threshold        = optional(number, 0.05)
    ttl_seconds            = optional(number, 300)
    ignore_system_messages = optional(bool, true)
    max_message_count      = optional(number, 10)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.semantic_cache.score_threshold >= 0 && var.semantic_cache.score_threshold <= 1
    error_message = "semantic_cache.score_threshold must be between 0.0 and 1.0."
  }
  validation {
    condition     = var.semantic_cache.ttl_seconds >= 1 && var.semantic_cache.max_message_count >= 1 && floor(var.semantic_cache.ttl_seconds) == var.semantic_cache.ttl_seconds && floor(var.semantic_cache.max_message_count) == var.semantic_cache.max_message_count
    error_message = "semantic_cache.ttl_seconds and max_message_count must be whole numbers, at least 1."
  }
  validation {
    condition     = var.semantic_cache.embeddings_url == null || can(regex("^https://[^?]+$", coalesce(var.semantic_cache.embeddings_url, "-")))
    error_message = "semantic_cache.embeddings_url must be an https URL without a query string."
  }
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
