variable "convention" {
  description = "Naming convention. \"v1\" reproduces the names this repository has always generated (resource_token + random suffix), so existing deployments keep their names."
  type        = string
  default     = "v1"

  validation {
    condition     = contains(["v1"], var.convention)
    error_message = "convention must be \"v1\" (the AVM-based convention arrives with the stacks in Phase 3)."
  }
}

variable "environment_name" {
  description = "Environment name used in resource names (e.g. citadel-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Explicit resource group name, or \"\" to derive rg-<environment_name>. Also part of the resource_token seed."
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "Subscription ID; part of the resource_token seed."
  type        = string
}

variable "legacy_suffix" {
  description = "The 6-character random suffix (random_string.suffix) that v1 appends to globally unique names."
  type        = string
}

variable "foundry_instance_names" {
  description = "Explicit Foundry account names, one per instance (\"\" = generate aif-<env>-<index>-<suffix>)."
  type        = list(string)
  default     = []
}

variable "name_overrides" {
  description = "Logical role => explicit name. Overrides win over generated names (keys: see the names output)."
  type        = map(string)
  default     = {}
}
