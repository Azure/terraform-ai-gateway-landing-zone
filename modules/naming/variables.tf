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
