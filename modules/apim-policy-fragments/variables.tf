variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

variable "fragments" {
  description = "Fragment ID => { xml, description }. Managed with azurerm_api_management_policy_fragment."
  type = map(object({
    xml         = string
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.fragments) : can(regex("^[A-Za-z0-9-]{1,80}$", k))])
    error_message = "Fragment IDs must be 1-80 letters, digits or hyphens."
  }
}

variable "azapi_fragments" {
  description = "Fragment ID => { xml, description }, managed with azapi_resource (direct PUT). Use for fragments that hit the azurerm LRO polling bug (404 PolicyFragment not found)."
  type = map(object({
    xml         = string
    description = optional(string, "")
  }))
  default = {}
}

variable "depends_on_ids" {
  description = "IDs of objects the fragments reference by name (named values). APIM validates those references when a fragment is saved, so the fragments wait for them."
  type        = list(string)
  default     = []
}

variable "usage_event" {
  description = <<-EOT
    Usage events inside fragments. A fragment can't include another fragment, so the module expands
    every marker comment `<!-- usage-event status="403" reason="validate-model-access" -->` (written
    right before a `<return-response>`) into the usage event body (templates/usage-event.xml.tftpl, the
    same body as the usage-event fragment). It's a no-op unless the request belongs to an access contract with
    usage_events, or record_key_rejections is on and the request has no subscription.
      record_key_rejections  also record rejections without a subscription key (security-handler)
  EOT
  type = object({
    record_key_rejections = optional(bool, false)
  })
  default  = {}
  nullable = false
}
