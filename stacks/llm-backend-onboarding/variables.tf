variable "foundry_backends" {
  description = <<-EOT
    LLM backends derived from the Foundry accounts of stacks/platform: ONE backend per
    account, serving every model deployed on it (read from Azure, so this file doesn't
    repeat the platform configuration). The first account has priority 1, the others
    priority 2, all weight 100.
      enabled          false = no derived backends: only llm_backends are deployed
                       (platform foundry.enabled = false, or Foundry accounts that
                       stacks/platform doesn't own).
      account_names    null = every account in the workload resource group whose name
                       starts with aif-<workload>-<environment>- (the naming contract).
      api_version      Inference API version for the derived models.
      session_aware_models
                       Derived models that are stateful (OpenAI Responses, Assistants): the pools
                       that serve them get session affinity (see session_affinity).
      circuit_breaker  Circuit breaker of every derived backend: the same options as
                       llm_backends[*].circuit_breaker.
  EOT
  type = object({
    enabled              = optional(bool, true)
    account_names        = optional(list(string))
    api_version          = optional(string, "2024-02-15-preview")
    session_aware_models = optional(list(string), [])
    circuit_breaker = optional(object({
      enabled            = optional(bool, true)
      failure_count      = optional(number, 3)
      failure_interval   = optional(string, "PT5M")
      trip_duration      = optional(string, "PT1M")
      status_code_ranges = optional(list(object({ min = number, max = number })), [{ min = 429, max = 429 }, { min = 500, max = 503 }])
      error_reasons      = optional(list(string), ["Server errors"])
      accept_retry_after = optional(bool, true)
    }), {})
  })
  default  = {}
  nullable = false
}

variable "llm_backends" {
  description = <<-EOT
    LLM backends deployed IN ADDITION to the Foundry-derived ones (foundry_backends): Azure
    OpenAI outside Foundry, third-party OpenAI-compatible endpoints, AWS Bedrock, Foundry
    accounts that stacks/platform doesn't own. Set foundry_backends.enabled = false to
    deploy only these. One entry per endpoint, each becoming one APIM backend:
      backend_id        unique APIM backend name (also across the Foundry-derived ones,
                        named foundry-<region>-<index>)
      backend_type      ai-foundry | azure-openai | external | aws-bedrock | aws-bedrock-mantle |
                        gemini | gemini-openai | anthropic | azure-flux | azure-mai
      endpoint          base URL
      auth_type         managed-identity | aws-sigv4 | api-key-bearer | api-key-header |
                        api-key-gemini | api-key-anthropic | none.
                        Default by backend_type: ai-foundry, azure-openai, azure-flux and azure-mai =
                        managed-identity, external = none, aws-bedrock = aws-sigv4,
                        aws-bedrock-mantle and gemini-openai = api-key-bearer, gemini =
                        api-key-gemini, anthropic = api-key-anthropic. (auth_scheme is legacy and ignored.)
      auth_config       named_value_key + key_vault_secret_uri (versionless; secret_value is for tests only).
                        Needed for api-key-bearer and api-key-header: APIM sends the named value as the
                        header of the backend (Authorization or api-key), so the Key Vault secret must hold
                        the COMPLETE header value: "Bearer <key>" for api-key-bearer, the bare key for
                        api-key-header. aws-sigv4 uses the aws variable instead.
      supported_models  models served: name, sku, capacity, modelFormat, modelVersion, apiVersion,
                        timeout, inferenceApiVersion, retirementDate, plus
                        modelPath (azure-flux: the Black Forest Labs slug, e.g. FLUX.2-pro = flux-2-pro) and
                        sessionAwareModel (a stateful model: its pools get session affinity)
      priority / weight load-balancing within a pool (models served by 2+ backends of one type get a pool)
      session_affinity  cookie_name / source of the affinity cookie of the pools of its stateful models
                        (overrides the stack's session_affinity)
      circuit_breaker   One rule per backend; every property is optional:
        enabled             false = no circuit breaker (default true).
        failure_count       Failures within failure_interval that trip it (3).
        failure_interval    ISO 8601 window in which failures are counted (PT5M).
        trip_duration       ISO 8601 time the backend stays out of rotation (PT1M).
        status_code_ranges  HTTP status ranges counted as failures, 200-599, at most 10
                            ([429], [500-503]).
        error_reasons       APIM error reasons counted as failures, at most 10 (["Server errors"]).
        accept_retry_after  Honour the Retry-After header of the backend as trip duration (true).
  EOT
  type = list(object({
    backend_id   = string
    backend_type = string
    endpoint     = string
    auth_scheme  = optional(string)
    auth_type    = optional(string)
    auth_config = optional(object({
      named_value_key      = optional(string)
      key_vault_secret_uri = optional(string)
      secret_value         = optional(string)
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
      modelPath           = optional(string, "")
      sessionAwareModel   = optional(bool, false)
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
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
  default  = []
  nullable = false
}

variable "model_aliases" {
  description = <<-EOT
    Model aliases: a client-facing name that resolves to real models.
      name      what clients send as the model
      models    real models, in order; they may live on different backends and clouds
      strategy  priority (first first, the rest are fallbacks on 429/5xx) | weighted
      weights   one per model for weighted
    Members of an alias must speak the API of the inbound surface (e.g. all OpenAI-compatible).
  EOT
  type = list(object({
    name     = string
    models   = list(string)
    strategy = optional(string, "priority")
    weights  = optional(list(number), [])
  }))
  default  = []
  nullable = false
}

variable "session_affinity" {
  description = <<-EOT
    Session affinity (sticky routing) of the backend pools of stateful models (a model flagged
    sessionAwareModel, or listed in foundry_backends.session_aware_models): APIM sets an affinity
    cookie and routes a client that replays it back to the same backend, as the OpenAI Responses
    and Assistants APIs require. Clients must keep the cookie (a cookie jar).
      enabled      master switch; false = no pool gets session affinity.
      cookie_name  name of the affinity cookie.
      source       APIM supports Cookie only.
  EOT
  type = object({
    enabled     = optional(bool, true)
    cookie_name = optional(string, "ai-gateway-affinity")
    source      = optional(string, "Cookie")
  })
  default  = {}
  nullable = false
}

variable "anthropic_version" {
  description = "Value of the anthropic-version header sent to api-key-anthropic backends (the anthropic-version named value)."
  type        = string
  default     = "2023-06-01"
}

variable "inference_api_type" {
  description = "Universal LLM API contract: AzureOpenAI, AzureAI, OpenAI or OpenAIV1."
  type        = string
  default     = "OpenAIV1"

  validation {
    condition     = contains(["AzureOpenAI", "AzureAI", "OpenAI", "OpenAIV1"], var.inference_api_type)
    error_message = "inference_api_type must be one of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  }
}

variable "features" {
  description = "Optional LLM APIs: unified_ai_api (+ product), ai_model_inference, openai_realtime; api_center_onboarding registers the LLM APIs in API Center."
  type = object({
    unified_ai_api        = optional(bool, false)
    ai_model_inference    = optional(bool, false)
    openai_realtime       = optional(bool, false)
    api_center_onboarding = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "aws" {
  description = "AWS Bedrock credentials (Key Vault references, versionless secret URIs) and region; \"\" = NOT_CONFIGURED placeholders."
  type = object({
    region                = optional(string, "")
    access_key_secret_uri = optional(string, "")
    secret_key_secret_uri = optional(string, "")
  })
  default  = {}
  nullable = false
}
