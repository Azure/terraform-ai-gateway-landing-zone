variable "workload" {
  description = "Short workload code used in every resource name (2-8 lowercase letters or digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.workload))
    error_message = "workload must be 2-8 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or digits."
  }
}

variable "subscription_id" {
  description = "Workload subscription ID; seeds the unique suffix when unique_seed is null."
  type        = string
}

variable "unique_seed" {
  description = "Suffix for globally unique names (5 lowercase letters or digits). null = derived from subscription_id, workload and environment."
  type        = string
  default     = null

  validation {
    condition     = var.unique_seed == null || can(regex("^[a-z0-9]{5}$", coalesce(var.unique_seed, "-")))
    error_message = "unique_seed must be 5 lowercase letters or digits."
  }
}

variable "foundry_instance_names" {
  description = "Explicit Foundry account names, one per instance (\"\" = generate aif-<workload>-<environment>-<seed>-<index>)."
  type        = list(string)
  default     = []
}

variable "name_overrides" {
  description = "Logical role => explicit name. Non-empty overrides win over generated names (keys: see the names output)."
  type        = map(string)
  default     = {}
}
