# =============================================================================
# Azure OpenAI API submodule — variables
# Mirrors bicep/infra/modules/apim/inference-api.bicep (inferenceAPIType=AzureOpenAI)
# =============================================================================

variable "apim_name" {
  description = "Name of the parent API Management service."
  type        = string
}

variable "apim_id" {
  description = "Resource ID of the parent API Management service."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "api_name" {
  type    = string
  default = "azure-openai-api"
}

variable "api_display_name" {
  type    = string
  default = "Azure OpenAI API"
}

variable "api_description" {
  type    = string
  default = "Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
}

# Bicep parity: path is `${inferenceAPIPath}/${endpointPath}` where
# inferenceAPIPath='' and endpointPath='openai' for AzureOpenAI inference type.
variable "api_path" {
  type    = string
  default = "openai"
}

variable "subscription_required" {
  description = "Bicep parity: `allowSubscriptionKey` (true unless Entra-only)."
  type        = bool
  default     = true
}

variable "openapi_spec_path" {
  description = "Absolute path to the OpenAPI spec JSON file imported into APIM (AIFoundryOpenAI.json)."
  type        = string
}

variable "policy_xml_path" {
  description = "Absolute path to the API-level inbound policy XML (azure-open-ai-api-policy.xml)."
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

variable "has_llm_backends" {
  description = "When false, skip operation policies that reference the dynamic get-available-models fragment."
  type        = bool
  default     = false
}

variable "app_insights_logger_id" {
  description = "APIM Application Insights logger resource ID."
  type        = string
  default     = ""
}

variable "azure_monitor_logger_id" {
  description = "APIM Azure Monitor logger resource ID."
  type        = string
  default     = ""
}

variable "app_insights_log_settings" {
  description = "Bicep parity: `appInsightsLogSettings`."
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
  description = "Resources the API-level policy depends on (named values, fragments)."
  type        = any
  default     = []
}
