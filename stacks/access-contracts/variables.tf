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
  description = <<-EOT
    Services to onboard: a product, its policy and a subscription each (modules/access-contract).
      code                     key in api_name_mapping, e.g. LLM
      endpoint_secret_name     Key Vault secret for the endpoint URL
      api_key_secret_name      Key Vault secret for the subscription key
    The product policy is generated from these properties:
      allowed_models           models (and aliases) the contract may call; [] = every model
      token_limit              per-subscription limit (llm-token-limit): tokens_per_minute and / or
                               token_quota, with token_quota_period (Hourly | Daily | Weekly | Monthly | Yearly);
                               null = no limit
      enable_response_headers  the UAIG-* debug response headers (default true)
      jwt_required             also validate the Entra token the Foundry connection sends
                               (audience = foundry_config.managed_identity_audience, tenant = the deploying identity's)
    policy_xml                 advanced: a complete product policy that replaces the generated one
                               (the properties above are then ignored)
  EOT
  type = list(object({
    code                 = string
    endpoint_secret_name = string
    api_key_secret_name  = string

    allowed_models = optional(list(string), [])
    token_limit = optional(object({
      tokens_per_minute  = optional(number)
      token_quota        = optional(number)
      token_quota_period = optional(string, "Monthly")
    }))
    enable_response_headers = optional(bool, true)
    jwt_required            = optional(bool, false)

    policy_xml = optional(string, "")
  }))

  validation {
    condition     = length(var.services) == length(distinct([for s in var.services : s.code]))
    error_message = "services[*].code must be unique."
  }
  validation {
    condition     = alltrue([for s in var.services : alltrue([for m in s.allowed_models : can(regex("^[A-Za-z0-9][A-Za-z0-9._:/-]*$", m))])])
    error_message = "services[*].allowed_models entries must be model or alias names (letters, digits and . _ : / -), without spaces or commas."
  }
  validation {
    condition = alltrue([for s in var.services : s.token_limit == null ? true : (
      (s.token_limit.tokens_per_minute != null || s.token_limit.token_quota != null) &&
      coalesce(s.token_limit.tokens_per_minute, 1) > 0 &&
      coalesce(s.token_limit.token_quota, 1) > 0
    )])
    error_message = "services[*].token_limit needs tokens_per_minute and / or token_quota, each greater than 0."
  }
  validation {
    condition     = alltrue([for s in var.services : s.token_limit == null ? true : contains(["Hourly", "Daily", "Weekly", "Monthly", "Yearly"], s.token_limit.token_quota_period)])
    error_message = "services[*].token_limit.token_quota_period must be Hourly, Daily, Weekly, Monthly or Yearly."
  }
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
