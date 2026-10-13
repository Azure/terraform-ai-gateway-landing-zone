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
    Services to onboard; each gets a product, its policy and a subscription.
      code                     key in api_name_mapping, e.g. LLM
      endpoint_secret_name     Key Vault secret for the endpoint URL
      api_key_secret_name      Key Vault secret for the subscription key
    The product policy is generated from these properties:
      allowed_models           models (and aliases) the contract may call; [] = every model
      token_limit              per-subscription limit (llm-token-limit): tokens_per_minute and / or
                               token_quota, with token_quota_period (Hourly | Daily | Weekly | Monthly | Yearly);
                               null = no limit
      enable_response_headers  the UAIG-* debug response headers (set-response-headers fragment)
      jwt_required             also require a valid JWT next to the subscription key (security-handler fragment:
                               Authorization: Bearer <token>; no token or an invalid one -> 401). By default the
                               token is validated against the gateway's identity provider (gateway-config
                               entra_auth: the JWT-* named values, i.e. tokens issued for the stacks/identity
                               app). A contract with a Foundry connection in ProjectManagedIdentity mode
                               validates the project identity's token instead (audience =
                               foundry_config.managed_identity_audience, tenant = tenant_id).
      jwt_audience             override the expected audience (aud claim), e.g. another app or provider
      jwt_issuer               override the expected issuer (iss claim)
      jwt_openid_config_url    override the OpenID Connect discovery URL (signing keys); with an issuer
                               of another tenant or provider (e.g. Auth0) set all three
      required_roles           app roles of which the token must carry at least one (roles claim, OR logic),
                               e.g. ["Models.Read"]; missing -> 403. Needs jwt_required.
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
    # The security-handler checks roles and the overrides only inside its jwtRequired branch.
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

variable "tenant_id" {
  description = "Entra tenant ID of the Foundry project identity's tokens: the issuer of the generated JWT policy for a contract with a ProjectManagedIdentity Foundry connection (services[*].jwt_required). Not used otherwise."
  type        = string
  default     = ""

  validation {
    condition = (
      var.foundry_project_id == null || var.foundry_config.auth_type != "ProjectManagedIdentity"
      || !anytrue([for s in var.services : s.jwt_required && s.policy_xml == "" && (s.jwt_issuer == null || s.jwt_openid_config_url == null)])
      || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    )
    error_message = "tenant_id (a GUID) is required when a contract with a ProjectManagedIdentity Foundry connection sets jwt_required (without its own jwt_issuer and jwt_openid_config_url, or policy_xml)."
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
    Foundry connection settings.
      connection_name_prefix  "" = Hub-<bu>-<usecase>-<env>
      connection_category     ApiManagement | ModelGateway
      auth_type               ProjectManagedIdentity (default) | ApiKey.
                              ProjectManagedIdentity: the Foundry project's managed identity sends an
                              Entra JWT for managed_identity_audience AND the subscription key travels
                              as the `api-key` custom header (no stored credential). The product policy
                              must validate that JWT (jwtRequired + jwtAudience/jwtIssuer/jwtOpenIdConfigUrl,
                              see DEPLOYMENT_GUIDE "Foundry connection authentication"); a check warns when
                              it doesn't. ApiKey: the subscription key is the stored credential.
      managed_identity_audience
                              Audience the project identity requests a token for; must equal the audience
                              the product policy validates. Only for ProjectManagedIdentity.
      deployment_in_path      "true" (model in path) | "false" (model in body)
      is_shared_to_all, inference_api_version, deployment_api_version, static_models,
      list_models_endpoint, get_model_endpoint, deployment_provider ("" | AzureOpenAI | OpenAI),
      custom_headers (the api-key header is added automatically for ProjectManagedIdentity), auth_config
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
  validation {
    condition     = var.foundry_config.auth_type != "ProjectManagedIdentity" || trimspace(var.foundry_config.managed_identity_audience) != ""
    error_message = "foundry_config.managed_identity_audience can't be empty with auth_type = ProjectManagedIdentity."
  }
  validation {
    condition     = !contains(keys(var.foundry_config.custom_headers), "api-key") || var.foundry_config.auth_type != "ProjectManagedIdentity"
    error_message = "foundry_config.custom_headers can't set api-key with auth_type = ProjectManagedIdentity: the subscription key is added automatically."
  }

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
