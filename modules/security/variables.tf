variable "resource_group_name" {
  description = "Name of the resource group the module deploys into."
  type        = string
}
variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}
variable "key_vault_name" {
  description = "Name of the Key Vault."
  type        = string
}
variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
}
variable "tenant_id" {
  description = "Entra tenant ID for the Key Vault."
  type        = string
}
variable "deployer_object_id" {
  description = "Object ID of the identity running Terraform; granted Key Vault data-plane access so it can write secrets."
  type        = string
}
variable "managed_identity_principal_id" {
  description = "Principal ID of the APIM managed identity granted Key Vault Secrets User."
  type        = string
}
variable "subnet_id" {
  description = "Resource ID of the subnet that hosts the private endpoint."
  type        = string
}
variable "dns_zone_id_key_vault" {
  description = "Resource ID of the privatelink.vaultcore.azure.net DNS zone (empty = no DNS zone group)."
  type        = string
}
variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vaults (1-90, default 7)"
  type        = number
  default     = 7
}
variable "purge_protection_enabled" {
  description = "Enable purge protection on Key Vault (prevents permanent deletion)"
  type        = bool
}
variable "rbac_authorization_enabled" {
  description = "Enable RBAC authorization on Key Vault"
  type        = bool
}
variable "network_acl_default_action" {
  description = "Default network access action for Key Vault (Allow or Deny)"
  type        = string
  default     = "Deny"
}
variable "public_network_access_enabled" {
  description = "Allow public network access to the Key Vault."
  type        = bool
}
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
