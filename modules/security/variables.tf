variable "resource_group_name"          { type = string }
variable "location"                       { type = string }
variable "tags"                           { type = map(string) }
variable "key_vault_name"                 { type = string }
variable "key_vault_sku"                  { type = string }
variable "tenant_id"                      { type = string }
variable "deployer_object_id"             { type = string }
variable "managed_identity_principal_id"  { type = string }
variable "managed_identity_id"            { type = string }
variable "subnet_id"                      { type = string }
variable "vnet_id"                        { type = string }
variable "dns_zone_id_key_vault"          { type = string }
variable "soft_delete_retention_days"     { 
    type = number
    default = 7
}
variable "purge_protection_enabled"       { type = bool }
variable "rbac_authorization_enabled"     { type = bool }
variable "network_acl_default_action"     { 
    type = string 
    default = "Deny"
}
variable "public_network_access_enabled" { type = bool }
variable "ip_rules" {
  description = "Optional list of public IPs / CIDRs to add to Key Vault network_acls.ip_rules (for bootstrap/data-plane writes from the deployer)."
  type        = list(string)
  default     = []
}
variable "foundry_principal_ids" {
  description = "System-assigned principal IDs of AI Foundry accounts for KV Secrets User grant (Bicep: keyvault-rbac.bicep)."
  type        = list(string)
  default     = []
}

variable "foundry_principal_count" {
  description = "Number of Foundry principals — must be known at plan time so `count` works. Caller should pass `length(var.ai_foundry_instances)` (or 0 when Foundry disabled)."
  type        = number
  default     = 0
}

variable "create_apim_gateway_key_secret" {
  description = <<-EOT
    Create a placeholder `apim-gateway-key` secret in Key Vault. Disabled by
    default — nothing in the Terraform stack consumes it programmatically
    (only notebook samples reference it, and they fetch the key out-of-band
    via `az apim`). Creating it requires KV data-plane write access from the
    deployer IP and commonly trips the KV firewall on locked-down
    environments. Set to `true` only if you have downstream tooling that
    reads `apim-gateway-key` from KV directly.
  EOT
  type        = bool
  default     = false
}
