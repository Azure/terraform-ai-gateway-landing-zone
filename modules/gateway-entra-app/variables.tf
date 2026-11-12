variable "display_name" {
  description = "Display name of the app registration (the naming contract's gateway_app: other stacks look the app up by this name)."
  type        = string
}

variable "owners" {
  description = "Additional owner object IDs (the identity running Terraform is always an owner)."
  type        = set(string)
  default     = []
}
