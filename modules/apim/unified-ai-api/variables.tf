# =============================================================================
# Unified AI Wildcard API submodule — variables
# Mirrors bicep/infra/modules/apim/unified-ai-api.bicep
# =============================================================================

variable "apim_name" {
  description = "Name of the parent API Management service."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name. Leave empty for auto-generated."
  type        = string
}

variable "api_name" {
  description = "Name (ID) of the API in API Management."
  type        = string
  default     = "unified-ai-api"
}

variable "api_display_name" {
  description = "Display name of the API in API Management."
  type        = string
  default     = "Unified AI API"
}

variable "api_description" {
  description = "Description of the API in API Management."
  type        = string
  default     = "Unified AI Gateway API - Routes requests to multiple AI model providers (Azure OpenAI, AI Foundry, Gemini) using dynamic path-based routing with support for multiple API types."
}

variable "api_path" {
  description = "URL path suffix of the API on the APIM gateway."
  type        = string
  default     = "unified-ai"
}

variable "subscription_required" {
  description = "Bicep parity: subscriptionRequired (always true for unified-ai-api)."
  type        = bool
  default     = true
}

variable "openapi_spec_path" {
  description = "Absolute path to the OpenAPI spec JSON file imported into APIM (UnifiedAIWildcard.json)."
  type        = string
}

variable "policy_xml_path" {
  description = "Absolute path to the API-level inbound policy XML (unified-ai-api-policy.xml)."
  type        = string
}

variable "deployments_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /deployments."
  type        = string
}

variable "deployment_by_name_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /deployments/{deployment-id}."
  type        = string
}

variable "product_policy_xml_path" {
  description = "Absolute path to the product policy XML (unified-ai-product-subscription.xml)."
  type        = string
}

variable "product_id" {
  description = "ID of the APIM product created for the Unified AI API."
  type        = string
  default     = "unified-ai-product"
}

variable "product_display_name" {
  description = "Display name of the Unified AI API product."
  type        = string
  default     = "Unified AI Gateway"
}

variable "product_description" {
  description = "Description of the Unified AI API product."
  type        = string
  default     = "Unified AI Gateway product - provides access to all AI model providers through a single wildcard endpoint."
}

variable "product_subscriptions_limit" {
  description = "Maximum number of subscriptions allowed on the product."
  type        = number
  default     = 10
}

variable "azure_monitor_logger_id" {
  description = "APIM Azure Monitor logger resource ID. When empty, the azuremonitor diagnostic is skipped."
  type        = string
  default     = ""
}

variable "azure_monitor_log_settings" {
  description = "Bicep parity: `azureMonitorLogSettings` — frontend/backend headers+body and largeLanguageModel logs."
  type = object({
    frontend = object({
      request  = object({ headers = list(string), body = object({ bytes = number }) })
      response = object({ headers = list(string), body = object({ bytes = number }) })
    })
    backend = object({
      request  = object({ headers = list(string), body = object({ bytes = number }) })
      response = object({ headers = list(string), body = object({ bytes = number }) })
    })
    largeLanguageModel = object({
      logs      = string
      requests  = object({ messages = string, maxSizeInBytes = number })
      responses = object({ messages = string, maxSizeInBytes = number })
    })
  })
  default = {
    frontend = {
      request  = { headers = [], body = { bytes = 0 } }
      response = { headers = [], body = { bytes = 0 } }
    }
    backend = {
      request  = { headers = [], body = { bytes = 0 } }
      response = { headers = [], body = { bytes = 0 } }
    }
    largeLanguageModel = {
      logs      = "enabled"
      requests  = { messages = "all", maxSizeInBytes = 262144 }
      responses = { messages = "all", maxSizeInBytes = 262144 }
    }
  }
}

variable "policy_dependencies" {
  description = "Resources the API-level policy depends on (named values, fragments)."
  type        = any
  default     = []
}
