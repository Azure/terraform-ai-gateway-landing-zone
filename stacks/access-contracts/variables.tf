variable "use_case" {
  description = "Use case descriptor; products and subscriptions are named <code>-<business_unit>-<use_case_name>-<environment>."
  type = object({
    business_unit = string
    use_case_name = string
    environment   = string
  })
}

variable "api_name_mapping" {
  description = "Service code => names of published APIs, e.g. { LLM = [\"universal-llm-api\", \"azure-openai-api\"] }."
  type        = map(list(string))
}

variable "services" {
  description = "Services to onboard (code, endpoint_secret_name, api_key_secret_name, policy_xml); see modules/access-contract."
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

variable "key_vault" {
  description = "Where the endpoint and key secrets go. enabled = false: no secrets (endpoints in outputs, keys from APIM on demand). id null = the platform Key Vault; set it for a team-owned vault."
  type = object({
    enabled = optional(bool, true)
    id      = optional(string)
  })
  default  = {}
  nullable = false
}

variable "foundry" {
  description = "Foundry project that gets a connection per service. account_name \"\" = platform's primary account; project_id overrides both names (e.g. a team-owned project)."
  type = object({
    enabled      = optional(bool, false)
    account_name = optional(string, "")
    project_name = optional(string, "citadel-governance-project")
    project_id   = optional(string)
  })
  default  = {}
  nullable = false
}

variable "foundry_config" {
  description = <<-EOT
    Foundry connection settings (Bicep foundryConfig).
      connection_name_prefix  "" = Hub-<bu>-<usecase>-<env>
      connection_category     ApiManagement | ModelGateway
      auth_type               ProjectManagedIdentity (default) | ApiKey. With ProjectManagedIdentity the
                              Foundry project's managed identity sends an Entra JWT for
                              managed_identity_audience and the subscription key travels as the api-key
                              custom header; the product policy must validate that JWT (see modules/access-contract).
      managed_identity_audience  token audience; must equal the jwtAudience the product policy validates
      deployment_in_path      "true" (model in path) | "false" (model in body)
      is_shared_to_all, inference_api_version, deployment_api_version, static_models,
      list_models_endpoint, get_model_endpoint, deployment_provider ("" | AzureOpenAI | OpenAI),
      custom_headers, auth_config
  EOT
  type = object({
    connection_name_prefix = optional(string, "")
    connection_category    = optional(string, "ApiManagement")
    auth_type              = optional(string, "ProjectManagedIdentity")
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

    managed_identity_audience = optional(string, "https://cognitiveservices.azure.com")
  })
  default = {}

  validation {
    condition     = contains(["ProjectManagedIdentity", "ApiKey"], var.foundry_config.auth_type)
    error_message = "foundry_config.auth_type must be ProjectManagedIdentity or ApiKey."
  }
}

variable "secret_rotation_days" {
  description = "Days after which the key secrets are rewritten on the next apply."
  type        = number
  default     = 60
}

variable "secret_validity_days" {
  description = "Key Vault secret validity in days (ALZ Enforce-GR-KeyVault allows at most 90)."
  type        = number
  default     = 90
}
