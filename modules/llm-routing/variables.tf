variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

variable "llm_backend_config" {
  description = <<-EOT
    llmBackendConfig: one entry per LLM endpoint, each becoming one APIM backend.
      circuit_breaker  Per-backend circuit breaker rule (APIM allows one rule per backend):
        enabled             false = no circuit breaker on this backend.
        failure_count       Failures within failure_interval that trip the breaker.
        failure_interval    ISO 8601 window in which failures are counted (PT5M = 5 minutes).
        trip_duration       ISO 8601 time the backend stays out of rotation once tripped.
        status_code_ranges  HTTP status ranges counted as failures (200-599, at most 10).
        error_reasons       APIM error reasons counted as failures (at most 10).
        accept_retry_after  Honour a Retry-After header of the backend as the trip duration.
  EOT
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
}
variable "managed_identity_client_id" {
  description = "Client ID of the APIM user-assigned managed identity that authenticates to managed-identity backends."
  type        = string
}
