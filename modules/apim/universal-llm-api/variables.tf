# =============================================================================
# Universal LLM API submodule — variables
# Mirrors bicep/infra/modules/apim/inference-api.bicep (inferenceAPIType=AzureAI)
# =============================================================================

variable "apim_name" {
  description = "Name of the parent API Management service."
  type        = string
}

variable "apim_id" {
  description = "Resource ID of the parent API Management service. Used to derive logger IDs and for azapi diagnostics."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "api_name" {
  type    = string
  default = "universal-llm-api"
}

variable "api_display_name" {
  type    = string
  default = "Universal LLM API"
}

variable "api_description" {
  type    = string
  default = "Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
}

# Bicep parity: path is `${inferenceAPIPath}/${endpointPath}` where
# inferenceAPIPath='' and endpointPath='models' for AzureAI inference type.
variable "api_path" {
  type    = string
  default = "models"
}

variable "subscription_required" {
  description = "Bicep parity: `allowSubscriptionKey` (true unless Entra-only)."
  type        = bool
  default     = true
}

variable "openapi_spec_path" {
  description = "Absolute path to the OpenAPI spec JSON file imported into APIM."
  type        = string
}

variable "policy_xml_path" {
  description = "Absolute path to the API-level inbound policy XML."
  type        = string
}

variable "deployments_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /deployments."
  type        = string
  default     = ""
}

variable "deployment_by_name_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /deployments/{deployment-id}."
  type        = string
  default     = ""
}

# Bicep parity: inference-api.bicep `inferenceAPIType`. Selects the OpenAPI
# spec + base path. Default flipped AzureAI -> OpenAIV1 to match apim.bicep.
variable "inference_api_type" {
  type    = string
  default = "OpenAIV1"
  validation {
    condition     = contains(["AzureOpenAI", "AzureAI", "OpenAI", "OpenAIV1"], var.inference_api_type)
    error_message = "inference_api_type must be one of AzureOpenAI, AzureAI, OpenAI, OpenAIV1."
  }
}

variable "list_models_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /models (OpenAIV1 only)."
  type        = string
  default     = ""
}

variable "retrieve_model_op_policy_xml_path" {
  description = "Absolute path to the operation-policy XML for GET /models/{model} (OpenAIV1 only)."
  type        = string
  default     = ""
}

variable "has_llm_backends" {
  description = "When false, skip operation policies that reference the dynamic get-available-models fragment."
  type        = bool
  default     = false
}

variable "app_insights_logger_id" {
  description = "APIM Application Insights logger resource ID. Empty string disables the appinsights diagnostic."
  type        = string
  default     = ""
}

variable "azure_monitor_logger_id" {
  description = "APIM Azure Monitor logger resource ID. Empty string disables the azuremonitor diagnostic. Note: managed via azapi; the LLM log block is included for Bicep parity."
  type        = string
  default     = ""
}

variable "app_insights_log_settings" {
  description = "Bicep parity: `appInsightsLogSettings` — headers + body bytes captured by the applicationinsights diagnostic."
  type = object({
    headers = list(string)
    body    = object({ bytes = number })
  })
  default = {
    headers = ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"]
    body    = { bytes = 0 }
  }
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
  description = "Resources the API-level policy depends on (named values, fragments). Pass any IDs/refs to force ordering."
  type        = any
  default     = []
}
