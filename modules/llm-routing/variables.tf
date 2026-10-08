variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

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
variable "configure_circuit_breaker" {
  description = "Enable per-backend circuit breaker rules."
  type        = bool
  default     = true
}
variable "managed_identity_client_id" {
  description = "Client ID of the APIM user-assigned managed identity that authenticates to managed-identity backends."
  type        = string
}
