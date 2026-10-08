variable "foundry_backends" {
  description = <<-EOT
    LLM backends derived from the Foundry accounts of stacks/platform: one backend per
    account, serving every model deployed on it (read from Azure, so this file doesn't
    repeat the platform configuration).
      enabled        false = only llm_backend_config / extra_llm_backends.
      account_names  null = every account in the workload resource group whose name
                     starts with aif-<workload>-<environment>- (the naming contract).
      api_version    Inference API version for the derived models.
  EOT
  type = object({
    enabled       = optional(bool, true)
    account_names = optional(list(string))
    api_version   = optional(string, "2024-02-15-preview")
  })
  default  = {}
  nullable = false
}

variable "llm_backend_config" {
  description = <<-EOT
    FULL override of the LLM backends (replaces the Foundry-derived list). One entry per endpoint:
      backend_id        unique id (APIM backend name)
      backend_type      ai-foundry | azure-openai | external | aws-bedrock
      endpoint          base URL
      auth_type         managed-identity | aws-sigv4 | api-key-bearer | api-key-header | none
      auth_config       named_value_key + key_vault_secret_uri (versionless; secret_value is for tests only)
      supported_models  models served (name, apiVersion, timeout, inferenceApiVersion, ...)
      priority / weight load-balancing within a pool
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
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
  }))
  default  = []
  nullable = false
}

variable "extra_llm_backends" {
  description = "Backends APPENDED to the Foundry-derived ones (e.g. Azure OpenAI outside Foundry, third-party endpoints, AWS Bedrock). Same shape as llm_backend_config; ignored when llm_backend_config is set."
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
    }))
    priority = optional(number, 1)
    weight   = optional(number, 100)
  }))
  default  = []
  nullable = false
}

variable "model_aliases" {
  description = "Model aliases: { name, models[], strategy (priority | weighted), weights[] }."
  type = list(object({
    name     = string
    models   = list(string)
    strategy = optional(string, "priority")
    weights  = optional(list(number), [])
  }))
  default  = []
  nullable = false
}

variable "configure_circuit_breaker" {
  description = "Per-backend circuit breaker rules (recommended for production)."
  type        = bool
  default     = true
}

variable "inference_api_type" {
  description = "Universal LLM API contract (Bicep inferenceAPIType): AzureOpenAI, AzureAI, OpenAI or OpenAIV1."
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
