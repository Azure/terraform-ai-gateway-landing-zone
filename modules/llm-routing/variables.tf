variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

variable "llm_backend_config" {
  description = <<-EOT
    llmBackendConfig: one entry per LLM endpoint, each becoming one APIM backend.
      backend_type     ai-foundry | azure-openai | aws-bedrock | aws-bedrock-mantle | gemini |
                       gemini-openai | anthropic | azure-flux | azure-mai | external.
      auth_type        managed-identity | aws-sigv4 | api-key-bearer | api-key-header |
                       api-key-gemini (x-goog-api-key) | api-key-anthropic (x-api-key and
                       anthropic-version) | none.
                       Default by backend_type: aws-bedrock = aws-sigv4, external = none,
                       aws-bedrock-mantle and gemini-openai = api-key-bearer, gemini =
                       api-key-gemini, anthropic = api-key-anthropic, otherwise
                       managed-identity. auth_scheme is legacy and ignored.
      auth_config      named_value_key: the APIM named value holding the key. APIM adds it as the
                       header of the backend (Authorization for api-key-bearer, api-key for
                       api-key-header), so the secret holds the COMPLETE header value
                       ("Bearer <key>" for api-key-bearer, the bare key for api-key-header).
      circuit_breaker  Per-backend circuit breaker rule (APIM allows one rule per backend):
        enabled             false = no circuit breaker on this backend.
        failure_count       Failures within failure_interval that trip the breaker.
        failure_interval    ISO 8601 window in which failures are counted (PT5M = 5 minutes).
        trip_duration       ISO 8601 time the backend stays out of rotation once tripped.
        status_code_ranges  HTTP status ranges counted as failures (200-599, at most 10).
        error_reasons       APIM error reasons counted as failures (at most 10).
        accept_retry_after  Honour a Retry-After header of the backend as the trip duration.
      session_affinity cookie_name / source of the affinity cookie of the pools this backend joins
                       (overrides the module's session_affinity); only pools of models flagged
                       sessionAwareModel get one.
  EOT
  type = list(object({
    backend_id   = string
    backend_type = string
    endpoint     = string
    auth_scheme  = optional(string) # legacy, ignored (auth_type decides)
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
      # Provider slug in the URL path of the backend: required for azure-flux models (the
      # Black Forest Labs slug differs from the model name, e.g. FLUX.2-pro = flux-2-pro).
      modelPath = optional(string, "")
      # A stateful model (OpenAI Responses, Assistants): the pools that serve it get session affinity.
      sessionAwareModel = optional(bool, false)
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
    # Per-backend override of the session cookie of the pools this backend joins.
    session_affinity = optional(object({
      cookie_name = optional(string)
      source      = optional(string)
    }))
    circuit_breaker = optional(object({
      enabled            = optional(bool, true)
      failure_count      = optional(number, 3)
      failure_interval   = optional(string, "PT5M")
      trip_duration      = optional(string, "PT1M")
      status_code_ranges = optional(list(object({ min = number, max = number })), [{ min = 429, max = 429 }, { min = 500, max = 503 }])
      error_reasons      = optional(list(string), ["Server errors"])
      accept_retry_after = optional(bool, true)
    }), {})
  }))
  default = []

  validation {
    condition     = length(distinct([for b in var.llm_backend_config : b.backend_id])) == length(var.llm_backend_config)
    error_message = "backend_id must be unique across all LLM backends (it is the APIM backend name), including the Foundry-derived ones named foundry-<region>-<index>."
  }

  validation {
    condition = alltrue([
      for b in var.llm_backend_config :
      contains(["api-key-bearer", "api-key-header", "api-key-gemini", "api-key-anthropic"], coalesce(b.auth_type,
        contains(["aws-bedrock-mantle", "gemini-openai"], b.backend_type) ? "api-key-bearer" :
        b.backend_type == "gemini" ? "api-key-gemini" :
      b.backend_type == "anthropic" ? "api-key-anthropic" : "-"))
      ? coalesce(try(b.auth_config.named_value_key, "-"), "-") != "-" : true
    ])
    error_message = "Backends with key authentication (api-key-bearer, api-key-header, api-key-gemini, api-key-anthropic, including the aws-bedrock-mantle, gemini-openai, gemini and anthropic types, which default to one) need auth_config.named_value_key."
  }

  validation {
    condition     = alltrue([for b in var.llm_backend_config : b.circuit_breaker.failure_count >= 1])
    error_message = "circuit_breaker.failure_count must be at least 1."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.llm_backend_config : [
        for d in [b.circuit_breaker.failure_interval, b.circuit_breaker.trip_duration] :
        can(regex("^P(\\d+D)?(T(\\d+H)?(\\d+M)?(\\d+S)?)?$", d)) && d != "P" && !endswith(d, "T")
      ]
    ]))
    error_message = "circuit_breaker.failure_interval and trip_duration must be ISO 8601 durations such as PT30S, PT1M, PT1H30M or P1D."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.llm_backend_config : concat(
        [length(b.circuit_breaker.status_code_ranges) <= 10],
        [for r in b.circuit_breaker.status_code_ranges : r.min >= 200 && r.max <= 599 && r.min <= r.max]
      )
    ]))
    error_message = "circuit_breaker.status_code_ranges: at most 10 ranges, each with 200 <= min <= max <= 599."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.llm_backend_config : concat(
        [length(b.circuit_breaker.error_reasons) <= 10],
        [for e in b.circuit_breaker.error_reasons : length(e) <= 200]
      )
    ]))
    error_message = "circuit_breaker.error_reasons: at most 10 entries of at most 200 characters."
  }
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

  validation {
    condition     = alltrue([for a in var.model_aliases : contains(["priority", "weighted"], a.strategy)])
    error_message = "Model alias strategy must be priority or weighted."
  }

  validation {
    condition     = alltrue([for a in var.model_aliases : length(a.weights) == 0 || length(a.weights) == length(a.models)])
    error_message = "Model alias weights need one weight per model."
  }
}

variable "session_affinity" {
  description = <<-EOT
    Session affinity (sticky routing) of the backend pools of stateful models (those flagged
    sessionAwareModel): APIM sets an affinity cookie and routes a client that replays it back to the
    same backend, as the OpenAI Responses and Assistants APIs require.
      enabled      master switch; false = no pool gets session affinity.
      cookie_name  name of the affinity cookie.
      source       where the session id lives; APIM supports Cookie only.
  EOT
  type = object({
    enabled     = optional(bool, true)
    cookie_name = optional(string, "ai-gateway-affinity")
    source      = optional(string, "Cookie")
  })
  default  = {}
  nullable = false

  validation {
    condition     = lower(var.session_affinity.source) == "cookie"
    error_message = "session_affinity.source must be Cookie: it is the only session id source APIM supports."
  }
}
variable "release_version" {
  description = "Version of this solution reported as masterVersion in the backend contract (the stack reads version.txt of release-please)."
  type        = string
  default     = "0.0.0"
}

variable "managed_identity_client_id" {
  description = "Client ID of the APIM user-assigned managed identity that authenticates to managed-identity backends."
  type        = string
}
