# =============================================================================
# Common inputs — IDENTICAL in every stack (scripts/ci/check-common-vars.sh).
# Values come from environments/<env>/common.tfvars.
# =============================================================================

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

# tflint-ignore: terraform_unused_declarations # not every stack uses every common input
variable "location" {
  description = "Primary Azure region (e.g. swedencentral)."
  type        = string
}

variable "subscription_id" {
  description = "Workload subscription ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "naming" {
  description = <<-EOT
    Naming inputs shared by all stacks (modules/naming, docs/naming.md).
      unique_seed     5 lowercase letters/digits; null = derived from subscription_id, workload and environment.
      name_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }).
  EOT
  type = object({
    unique_seed    = optional(string)
    name_overrides = optional(map(string), {})
  })
  default  = {}
  nullable = false
}

# tflint-ignore: terraform_unused_declarations # not every stack uses every common input
variable "tags" {
  description = "Tags applied to every resource (merged with workload, environment, stack and managed-by)."
  type        = map(string)
  default     = {}
  nullable    = false
}

# tflint-ignore: terraform_unused_declarations # not every stack uses every common input
variable "enable_telemetry" {
  description = "Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo."
  type        = bool
  default     = true
}

# tflint-ignore: terraform_unused_declarations # not every stack uses every common input
variable "network_mode" {
  description = <<-EOT
    greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.
    alz_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.
    byo         no network stack; platform.tfvars carries all IDs.
  EOT
  type        = string
  default     = "greenfield"

  validation {
    condition     = contains(["greenfield", "alz_spoke", "byo"], var.network_mode)
    error_message = "network_mode must be greenfield, alz_spoke or byo."
  }
}
