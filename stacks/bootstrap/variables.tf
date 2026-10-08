variable "stacks" {
  description = "Stacks that get a state container (one container per stack: separate locks and blast radius)."
  type        = list(string)
  default     = ["bootstrap", "identity", "network", "app-hosting", "platform", "gateway-config", "llm-backend-onboarding", "access-contracts"]
}

variable "github" {
  description = <<-EOT
    GitHub repository whose workflows deploy this environment (OIDC federated credentials).
      repository         owner/name.
      plan_environment   GitHub environment used by PR plans and drift checks (null = "<environment>-plan").
      apply_environment  GitHub environment used by applies on main (null = "<environment>").
    null = no federated credentials (local runs only).
  EOT
  type = object({
    repository        = string
    plan_environment  = optional(string)
    apply_environment = optional(string)
  })
  default = null
}

variable "pipeline_identity_mode" {
  description = "pair = a read-only plan identity + an apply identity (recommended); single = one identity for both (sandbox/dev only: PR plans then run with write rights)."
  type        = string
  default     = "pair"

  validation {
    condition     = contains(["pair", "single"], var.pipeline_identity_mode)
    error_message = "pipeline_identity_mode must be pair or single."
  }
}

variable "create_pipeline_identities" {
  description = "false = the identities already exist (e.g. created by ALZ subscription vending); pass their principal IDs in existing_pipeline_identities."
  type        = bool
  default     = true
}

variable "existing_pipeline_identities" {
  description = "Principal IDs of existing pipeline identities (create_pipeline_identities = false). plan_principal_id null = the apply identity also plans."
  type = object({
    apply_principal_id = string
    plan_principal_id  = optional(string)
  })
  default = null

  validation {
    condition     = var.create_pipeline_identities || var.existing_pipeline_identities != null
    error_message = "create_pipeline_identities = false needs existing_pipeline_identities."
  }
}

variable "create_workload_resource_group" {
  description = "Create the workload resource group (rg-<workload>-<environment>). false = it already exists (e.g. vended)."
  type        = bool
  default     = true
}

variable "graph_permissions" {
  description = "Grant Microsoft Graph application permissions to the pipeline identities: Application.Read.All (both) and Application.ReadWrite.OwnedBy (apply, for stacks/identity). Needs a Privileged Role Administrator. false = run stacks/identity as a human and set entra in gateway-config.tfvars."
  type        = bool
  default     = true
}

variable "policy_assignments" {
  description = "Grant the apply identity Resource Policy Contributor on the workload resource group (platform's deny_storage_shared_key assignment)."
  type        = bool
  default     = true
}

variable "additional_apply_role_assignments" {
  description = "Extra role assignments for the apply identity outside the workload resource group, e.g. Network Contributor on a vended VNet (alz_spoke) or Log Analytics Contributor on a platform workspace."
  type = map(object({
    scope                      = string
    role_definition_id_or_name = string
  }))
  default  = {}
  nullable = false
}

variable "state_storage" {
  description = <<-EOT
    Terraform state account (keyless: Entra ID only).
      replication                    ZRS (default) or another Standard SKU replication.
      public_network_access_enabled  false = private endpoint only (Corp): runners need a private path.
      allowed_ip_ranges              Public CIDRs allowed through the firewall (default action Deny when set).
      private_endpoint               subnet_id (+ private_dns_zone_id unless policy creates the zone group).
      retention_days                 Blob and container soft-delete retention.
  EOT
  type = object({
    replication                   = optional(string, "ZRS")
    public_network_access_enabled = optional(bool, true)
    allowed_ip_ranges             = optional(list(string), [])
    retention_days                = optional(number, 30)
    private_endpoint = optional(object({
      subnet_id           = string
      private_dns_zone_id = optional(string)
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.state_storage.replication)
    error_message = "state_storage.replication must be LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
  validation {
    condition     = var.state_storage.public_network_access_enabled || var.state_storage.private_endpoint != null
    error_message = "state_storage.public_network_access_enabled = false needs state_storage.private_endpoint."
  }
}

variable "state_admin_principal_ids" {
  description = "Principals (besides the person running bootstrap) that get Storage Blob Data Contributor on the state account, e.g. a break-glass group."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "resource_providers" {
  description = "Resource providers registered on the subscription (the pipeline identities can't register them)."
  type        = set(string)
  default = [
    "GitHub.Network",
    "Microsoft.ApiCenter",
    "Microsoft.ApiManagement",
    "Microsoft.App",
    "Microsoft.Cache",
    "Microsoft.CognitiveServices",
    "Microsoft.DocumentDB",
    "Microsoft.EventHub",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
    "Microsoft.Web",
  ]
}
