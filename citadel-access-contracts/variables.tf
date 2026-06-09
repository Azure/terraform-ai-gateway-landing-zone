# =============================================================================
# Citadel Access Contracts — Variables
#
# Bicep parity: citadel-access-contracts/main.bicep (subscription scope).
# Onboards a use-case to an existing AI Governance Hub APIM instance:
#   - Creates an APIM product + subscription per service code
#   - Attaches existing APIs to each product and applies an inbound policy
#   - Optionally writes endpoint + key secrets to Key Vault
#   - Optionally creates an Azure AI Foundry connection per service
# =============================================================================

# -----------------------------------------------------------------------------
# REQUIRED — Target APIM
# -----------------------------------------------------------------------------

variable "apim" {
  description = <<-EOT
    Existing API Management service coordinates.
    The Terraform provider is pinned to this subscription.
  EOT
  type = object({
    subscription_id     = string
    resource_group_name = string
    name                = string
  })
}

# -----------------------------------------------------------------------------
# REQUIRED — Use case identity (drives naming: <code>-<bu>-<usecase>-<env>)
# -----------------------------------------------------------------------------

variable "use_case" {
  description = "Use-case descriptor used in naming `<code>-<business_unit>-<use_case_name>-<environment>`."
  type = object({
    business_unit = string
    use_case_name = string
    environment   = string
  })
}

# -----------------------------------------------------------------------------
# REQUIRED — API name mapping + services
# -----------------------------------------------------------------------------

variable "api_name_mapping" {
  description = "Map of service code → list of API names already deployed in APIM. Example: { LLM = [\"universal-llm-api\", \"azure-openai-api\"] }"
  type        = map(list(string))
}

variable "services" {
  description = <<-EOT
    Services to onboard for this use case. Each item creates a product + subscription.

    Properties:
    - code:                 Service code (must be a key in api_name_mapping), e.g. "LLM"
    - endpoint_secret_name: Key Vault secret name for the gateway endpoint URL
    - api_key_secret_name:  Key Vault secret name for the subscription key
    - policy_xml:           (optional) Inbound product policy XML; empty = default policy
  EOT
  type = list(object({
    code                 = string
    endpoint_secret_name = string
    api_key_secret_name  = string
    policy_xml           = optional(string, "")
  }))
}

variable "product_terms" {
  description = "Product terms of service shown to subscribers."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# OPTIONAL — Key Vault output
# -----------------------------------------------------------------------------

variable "use_target_key_vault" {
  description = "If true, write endpoint + key secrets into Key Vault. If false, they are returned as (sensitive) outputs instead."
  type        = bool
  default     = true
}

variable "key_vault" {
  description = "Target Key Vault coordinates (required when use_target_key_vault = true)."
  type = object({
    subscription_id     = string
    resource_group_name = string
    name                = string
  })
  default = {
    subscription_id     = ""
    resource_group_name = ""
    name                = ""
  }
}

# -----------------------------------------------------------------------------
# OPTIONAL — Azure AI Foundry connection
# -----------------------------------------------------------------------------

variable "use_target_foundry" {
  description = "If true, create an Azure AI Foundry connection per service that points at the APIM gateway."
  type        = bool
  default     = false
}

variable "foundry" {
  description = "Azure AI Foundry coordinates (required when use_target_foundry = true)."
  type = object({
    subscription_id     = string
    resource_group_name = string
    account_name        = string
    project_name        = string
  })
  default = {
    subscription_id     = ""
    resource_group_name = ""
    account_name        = ""
    project_name        = ""
  }
}

variable "foundry_config" {
  description = <<-EOT
    Foundry connection configuration (mirrors the Bicep foundryConfig object).

    - connection_name_prefix: Custom connection-name prefix. Empty = "Hub-<bu>-<usecase>-<env>".
    - connection_category:    "ApiManagement" or "ModelGateway".
    - deployment_in_path:     "true" (model in URL path) or "false" (model in request body).
    - is_shared_to_all:       Share the connection with all project users.
    - inference_api_version:  API version for inference calls. Empty = APIM defaults.
    - deployment_api_version: API version for deployment discovery. Empty = APIM defaults.
    - static_models:          Static model list. Empty = dynamic discovery.
    - list_models_endpoint:   Custom list-models endpoint. Empty = APIM defaults.
    - get_model_endpoint:     Custom get-model endpoint. Empty = APIM defaults.
    - deployment_provider:    "", "AzureOpenAI", or "OpenAI" (used for custom discovery).
    - custom_headers:         Extra request headers.
    - auth_config:            Custom auth configuration object.
  EOT
  type = object({
    connection_name_prefix = optional(string, "")
    connection_category    = optional(string, "ApiManagement")
    deployment_in_path     = optional(string, "false")
    is_shared_to_all       = optional(bool, false)
    inference_api_version  = optional(string, "")
    deployment_api_version = optional(string, "")
    static_models          = optional(list(any), [])
    list_models_endpoint   = optional(string, "")
    get_model_endpoint     = optional(string, "")
    deployment_provider    = optional(string, "")
    custom_headers         = optional(map(string), {})
    auth_config            = optional(map(string), {})
  })
  default = {}

  validation {
    condition     = contains(["ApiManagement", "ModelGateway"], var.foundry_config.connection_category)
    error_message = "foundry_config.connection_category must be ApiManagement or ModelGateway."
  }

  validation {
    condition     = contains(["true", "false"], var.foundry_config.deployment_in_path)
    error_message = "foundry_config.deployment_in_path must be the string \"true\" or \"false\"."
  }

  validation {
    condition     = contains(["", "AzureOpenAI", "OpenAI"], var.foundry_config.deployment_provider)
    error_message = "foundry_config.deployment_provider must be \"\", \"AzureOpenAI\", or \"OpenAI\"."
  }
}
