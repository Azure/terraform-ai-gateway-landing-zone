variable "api_management" {
  description = "Target API Management service: id, name, resource group and gateway URL."
  type = object({
    id                  = string
    name                = string
    resource_group_name = string
    gateway_url         = string
  })
}

variable "use_case" {
  description = "Use case descriptor; products and subscriptions are named <code>-<business_unit>-<use_case_name>-<environment>."
  type = object({
    business_unit = string
    use_case_name = string
    environment   = string
  })
}

variable "api_name_mapping" {
  description = "Service code => names of APIs already published in APIM, e.g. { LLM = [\"universal-llm-api\", \"azure-openai-api\"] }."
  type        = map(list(string))
}

variable "api_paths" {
  description = "Service code => path of the first API in api_name_mapping (the endpoint written to Key Vault / used by Foundry)."
  type        = map(string)
}

variable "services" {
  description = <<-EOT
    Services to onboard; each gets a product (policy) and a subscription.
      code                  key in api_name_mapping, e.g. LLM
      endpoint_secret_name  Key Vault secret for the endpoint URL
      api_key_secret_name   Key Vault secret for the subscription key
      policy_xml            product policy; "" = policies/default-ai-product-policy.xml
  EOT
  type = list(object({
    code                 = string
    endpoint_secret_name = string
    api_key_secret_name  = string
    policy_xml           = optional(string, "")
  }))

  validation {
    condition     = length(var.services) == length(distinct([for s in var.services : s.code]))
    error_message = "services[*].code must be unique."
  }
}

variable "product_terms" {
  description = "Product terms of service shown to subscribers."
  type        = string
  default     = ""
}

variable "key_vault_id" {
  description = "Key Vault that receives the endpoint and key secrets (write-only: the key never enters state). null = no secrets."
  type        = string
  default     = null
}

variable "secret_rotation_days" {
  description = "Days after which the key secrets are rewritten and their expiry pushed forward on the next apply."
  type        = number
  default     = 60
}

variable "secret_validity_days" {
  description = "Key Vault secret validity (expiration_date) in days; ALZ Enforce-GR-KeyVault allows at most 90."
  type        = number
  default     = 90

  validation {
    condition     = var.secret_validity_days > var.secret_rotation_days
    error_message = "secret_validity_days must be greater than secret_rotation_days so secrets never expire between rotations."
  }
}

variable "foundry_project_id" {
  description = "Foundry project that gets one connection per service, pointing at the gateway (key passed write-only). null = no connection."
  type        = string
  default     = null
}

variable "foundry_config" {
  description = <<-EOT
    Foundry connection settings (Bicep foundryConfig).
      connection_name_prefix  "" = Hub-<bu>-<usecase>-<env>
      connection_category     ApiManagement | ModelGateway
      deployment_in_path      "true" (model in path) | "false" (model in body)
      is_shared_to_all, inference_api_version, deployment_api_version, static_models,
      list_models_endpoint, get_model_endpoint, deployment_provider ("" | AzureOpenAI | OpenAI),
      custom_headers, auth_config
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
