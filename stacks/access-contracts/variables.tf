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
      semantic_cache           serve similar chat completion prompts from the semantic cache (needs
                               gateway-config semantic_cache.enabled; default false)
      jwt_required             also require a valid JWT (Authorization: Bearer <token>) next to the key.
                               By default it is validated against the gateway's identity provider
                               (gateway-config entra_auth: tokens issued for the stacks/identity app);
                               with foundry.enabled in ProjectManagedIdentity mode, against the Foundry
                               project identity's token (audience = foundry_config.managed_identity_audience,
                               tenant = the deploying identity's)
      jwt_audience / jwt_issuer / jwt_openid_config_url
                               override the expected aud claim, iss claim and OpenID Connect discovery URL
                               (another tenant or provider, e.g. a partner tenant or Auth0); unset = default
      required_roles           app roles of which the token must carry at least one (roles claim), e.g.
                               ["Models.Read"]; missing -> 403. Needs jwt_required
    One product can grant a mix of asset types (LLM + tools (MCP) + agents (A2A)). List the granted
    tool and agent APIs by APIM API name (they must be in api_name_mapping[code]); every other API of the
    service is an LLM API, and allowed_models, token_limit and enable_response_headers apply to those only:
      tool_apis / agent_apis   API names granted as tools / agents ([] = none)
      tool_limit / agent_limit per-subscription request limits (rate-limit-by-key + quota-by-key):
                               calls_per_minute and / or call_quota, with call_quota_period
                               (Hourly | Daily | Weekly | Monthly | Yearly); null = no limit.
                               Needs the matching *_apis.
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
    semantic_cache          = optional(bool, false)
    jwt_required            = optional(bool, false)
    jwt_audience            = optional(string)
    jwt_issuer              = optional(string)
    jwt_openid_config_url   = optional(string)
    required_roles          = optional(list(string), [])

    tool_apis = optional(list(string), [])
    tool_limit = optional(object({
      calls_per_minute  = optional(number)
      call_quota        = optional(number)
      call_quota_period = optional(string, "Monthly")
    }))
    agent_apis = optional(list(string), [])
    agent_limit = optional(object({
      calls_per_minute  = optional(number)
      call_quota        = optional(number)
      call_quota_period = optional(string, "Monthly")
    }))

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
  validation {
    condition = alltrue([for s in var.services : alltrue([for a in concat(s.tool_apis, s.agent_apis) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", a))])]) && alltrue([
      for s in var.services : length(setintersection(toset(s.tool_apis), toset(s.agent_apis))) == 0
    ])
    error_message = "services[*].tool_apis / agent_apis entries must be APIM API names (letters, digits and . _ -), and an API can't be both a tool and an agent."
  }
  validation {
    condition     = alltrue([for s in var.services : alltrue([for a in concat(s.tool_apis, s.agent_apis) : contains(lookup(var.api_name_mapping, s.code, []), a)])])
    error_message = "Every API in services[*].tool_apis / agent_apis must also be listed in api_name_mapping for that service code, otherwise the product doesn't grant it."
  }
  validation {
    condition = alltrue([for s in var.services : alltrue([for l in [s.tool_limit, s.agent_limit] : l == null ? true : (
      (l.calls_per_minute != null || l.call_quota != null) &&
      coalesce(l.calls_per_minute, 1) > 0 &&
      coalesce(l.call_quota, 1) > 0 &&
      contains(["Hourly", "Daily", "Weekly", "Monthly", "Yearly"], l.call_quota_period)
    )])])
    error_message = "services[*].tool_limit / agent_limit need calls_per_minute and / or call_quota (each greater than 0) and a call_quota_period of Hourly, Daily, Weekly, Monthly or Yearly."
  }
  validation {
    condition     = alltrue([for s in var.services : (s.tool_limit == null || length(s.tool_apis) > 0) && (s.agent_limit == null || length(s.agent_apis) > 0)])
    error_message = "services[*].tool_limit needs tool_apis, and agent_limit needs agent_apis: without them no request is classified as a tool or agent and the limit would never apply."
  }
  validation {
    condition = alltrue([for s in var.services : s.jwt_required || (
      length(s.required_roles) == 0 && s.jwt_audience == null && s.jwt_issuer == null && s.jwt_openid_config_url == null
    )])
    error_message = "services[*].required_roles, jwt_audience, jwt_issuer and jwt_openid_config_url need jwt_required = true: without it no token is validated and they would never apply."
  }
  validation {
    condition     = alltrue([for s in var.services : alltrue([for r in s.required_roles : can(regex("^[A-Za-z0-9][A-Za-z0-9._:-]*$", r))])])
    error_message = "services[*].required_roles: app role values are letters, digits, '.', '_', ':' and '-' (no commas or spaces), e.g. Models.Read."
  }
  validation {
    condition = alltrue([for s in var.services : alltrue([
      for v in [s.jwt_audience, s.jwt_issuer, s.jwt_openid_config_url] : v == null || (length(trimspace(v)) > 0 && !strcontains(v, "{{"))
    ])])
    error_message = "services[*].jwt_audience / jwt_issuer / jwt_openid_config_url must be literal, non-empty values (leave them unset to use the gateway's named values)."
  }
  validation {
    condition     = alltrue([for s in var.services : alltrue([for v in [s.jwt_issuer, s.jwt_openid_config_url] : v == null || startswith(v, "https://")])])
    error_message = "services[*].jwt_issuer and jwt_openid_config_url must be https URLs."
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
    Foundry connection settings.
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
