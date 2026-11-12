variable "enabled" {
  description = "Register the APIs. Must be known at plan time (don't derive it from computed values)."
  type        = bool
}

variable "api_center_id" {
  description = "Resource ID of the API Center service the APIs are registered in."
  type        = string
}

variable "workspace_name" {
  description = "API Center workspace that receives the registrations."
  type        = string
  default     = "default"
}

variable "gateway_url" {
  description = "APIM gateway base URL; each deployment's runtime URI is <gateway_url>/<path>."
  type        = string
}

variable "apis" {
  description = "API name => registration details. kind: rest | websocket | mcp. environment: API Center environment name."
  type = map(object({
    display_name = string
    description  = string
    kind         = string
    path         = string
    environment  = string
  }))

  validation {
    condition     = alltrue([for a in var.apis : contains(["rest", "websocket", "mcp", "graphql", "grpc", "soap", "webhook"], a.kind)])
    error_message = "kind must be an API Center API kind (rest, websocket, mcp, ...)."
  }
}
