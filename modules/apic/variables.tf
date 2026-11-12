variable "resource_group_id" {
  description = "Resource ID of the resource group the module deploys into."
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}
variable "enable_api_center" {
  description = "Deploy API Center as AI Registry"
  type        = bool
}
variable "api_center_sku" {
  description = "SKU for API Center service. Free tier is 'Free', paid tier is 'Standard'."
  type        = string
}
variable "apic_location" {
  description = "Azure region for API Center (API Center isn't available in every region)."
  type        = string
}

variable "api_center_name" {
  description = "Name of the API Center service."
  type        = string
}

variable "remote_mcp_servers" {
  description = <<-EOT
    Remote (third-party) MCP servers to catalogue in API Center: an API of kind MCP, a version, a
    definition and a deployment each. They are not served by the gateway.
      name               API Center API name (letters, digits and hyphens), unique
      description        summary shown in the catalogue
      url                the server's MCP (SSE) endpoint: the deployment's runtime URI and the VS Code install link
      documentation_url  optional documentation link
  EOT
  type = list(object({
    name              = string
    description       = string
    url               = string
    documentation_url = optional(string, "")
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for m in var.remote_mcp_servers : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,89}$", m.name))])
    error_message = "remote_mcp_servers[*].name must be an API Center API name: letters, digits and hyphens, starting with a letter or digit."
  }
  validation {
    condition     = length(var.remote_mcp_servers) == length(distinct([for m in var.remote_mcp_servers : m.name]))
    error_message = "remote_mcp_servers[*].name must be unique."
  }
  validation {
    condition     = alltrue([for m in var.remote_mcp_servers : can(regex("^https?://[^\\s\"<>]+$", m.url)) && (m.documentation_url == "" || can(regex("^https?://[^\\s\"<>]+$", m.documentation_url)))])
    error_message = "remote_mcp_servers[*].url and documentation_url must be http(s) URLs without spaces, quotes or angle brackets."
  }
}
