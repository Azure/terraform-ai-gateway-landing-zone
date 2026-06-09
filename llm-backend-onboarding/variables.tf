# =============================================================================
# LLM Backend Onboarding — Variables
# =============================================================================

variable "subscription_id" {
  description = "Azure subscription ID where the APIM instance is deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "apim_name" {
  description = "Name of the existing API Management service."
  type        = string
}

variable "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity used by APIM for backend authentication."
  type        = string
}

variable "llm_backend_config" {
  description = <<-EOT
    Configuration array for LLM backends. Each entry represents an LLM endpoint.

    Properties:
    - backend_id:       Unique identifier (used in APIM backend resource name)
    - backend_type:     'ai-foundry' | 'azure-openai' | 'external' | 'aws-bedrock'
    - endpoint:         Base URL of the LLM service
    - auth_scheme:      'managedIdentity' | 'apiKey' | 'token'
    - auth_type:        (optional) 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'. Overrides legacy auth_scheme if set.
    - auth_config:      Object with auth details (e.g. named value key for API key)
    - supported_models: Array of model objects
    - priority:         1-5, default 1 (lower = higher priority)
    - weight:           1-1000, default 100 (load balancing weight)
  EOT
  type = list(object({
    backend_id   = string
    backend_type = string
    endpoint     = string
    auth_scheme  = optional(string)  # legacy, retained
    auth_type    = optional(string)  # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'
    auth_config  = optional(object({
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
}

variable "configure_circuit_breaker" {
  description = "Whether to configure circuit breaker for backends (recommended for production)."
  type        = bool
  default     = true
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