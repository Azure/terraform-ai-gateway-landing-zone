# =============================================================================
# ENTRA ID SETUP MODULE — Bicep parity (entra-id-setup/setup.ps1)
# =============================================================================

variable "environment_name" {
  description = "Environment name used to suffix the app registration display name (e.g. dev, prod)."
  type        = string
}

variable "app_display_name_prefix" {
  description = "Prefix for the app registration display name."
  type        = string
  default     = "ai-citadel-gateway"
}

variable "key_vault_id" {
  description = "Key Vault ID where the generated client secret will be stored."
  type        = string
}

variable "client_secret_name" {
  description = "Key Vault secret name for the client secret."
  type        = string
  default     = "ENTRA-APP-CLIENT-SECRET"
}

variable "client_secret_rotation_days" {
  description = "Trigger secret rotation when this many days have passed (default: 2 years)."
  type        = number
  default     = 730
}
