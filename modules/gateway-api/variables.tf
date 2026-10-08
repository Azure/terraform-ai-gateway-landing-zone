variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

variable "api_management_name" {
  description = "Name of the API Management service."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the API Management service."
  type        = string
}

variable "api" {
  description = <<-EOT
    The API to publish.
      type = "http": azurerm_api_management_api (OpenAPI import, subscription key names, optional service URL).
      type = "websocket" | "mcp": azapi Microsoft.ApiManagement/service/apis with `azapi_properties_json`
      (jsonencode of the ARM `properties` object; azurerm doesn't model these API types).
  EOT
  type = object({
    name                    = string
    type                    = optional(string, "http")
    display_name            = optional(string)
    description             = optional(string)
    path                    = optional(string)
    protocols               = optional(list(string), ["https"])
    service_url             = optional(string)
    subscription_required   = optional(bool, true)
    subscription_key_names  = optional(object({ header = string, query = string }))
    spec                    = optional(object({ format = string, value = string }))
    policy_xml              = optional(string)
    azapi_properties_json   = optional(string)
    azapi_schema_validation = optional(bool, true)
  })

  validation {
    condition     = contains(["http", "websocket", "mcp"], var.api.type)
    error_message = "api.type must be http, websocket or mcp."
  }
  validation {
    condition     = var.api.type != "http" || (var.api.display_name != null && var.api.path != null)
    error_message = "HTTP APIs need display_name and path."
  }
  validation {
    condition     = var.api.type == "http" || var.api.azapi_properties_json != null
    error_message = "WebSocket and MCP APIs need azapi_properties_json."
  }
  validation {
    condition     = var.api.path == null || !startswith(coalesce(var.api.path, "x"), "/")
    error_message = "api.path must not start with a slash."
  }
}

variable "operation_policies" {
  description = "Operation ID => policy XML, managed with azurerm_api_management_api_operation_policy (HTTP APIs)."
  type        = map(string)
  default     = {}
}

variable "azapi_operation_policies" {
  description = "Operation ID => policy XML, managed with azapi (Microsoft.ApiManagement/service/apis/operations/policies)."
  type        = map(string)
  default     = {}
}

variable "app_insights_diagnostic" {
  description = "API-level Application Insights diagnostic (plus the metrics flag azurerm doesn't expose). null = none."
  type = object({
    logger_id                 = string
    verbosity                 = string
    body_bytes                = number
    headers                   = list(string)
    http_correlation_protocol = optional(string, "W3C")
  })
  default = null
}

variable "azure_monitor_diagnostic" {
  description = "API-level Azure Monitor diagnostic. `properties` is the ARM properties object (includes largeLanguageModel logging). null = none."
  type = object({
    properties             = any
    response_export_values = optional(list(string))
  })
  default = null
}

variable "product" {
  description = "A product created together with the API (and linked to it). null = none."
  type = object({
    id                  = string
    display_name        = string
    description         = string
    subscriptions_limit = optional(number)
    policy_xml          = optional(string)
  })
  default = null
}

variable "policy_depends_on" {
  description = "IDs the API policies wait for (fragments, named values, loggers). APIM validates references when a policy is saved."
  type        = list(string)
  default     = []
}

variable "api_depends_on" {
  description = "IDs the API itself waits for (for example an MCP server's backend, or another API it is derived from)."
  type        = list(string)
  default     = []
}
