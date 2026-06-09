# =============================================================================
# MODULE: access-contracts — Input Variables
# =============================================================================

variable "apim_name" {
  description = "APIM service name."
  type        = string
}

variable "apim_resource_group_name" {
  description = "APIM resource group name."
  type        = string
}

variable "apim_gateway_url" {
  description = "APIM gateway URL (including https://)."
  type        = string
}

variable "use_case" {
  description = "Use-case descriptor — used in naming `<code>-<businessUnit>-<useCaseName>-<environment>`."
  type = object({
    business_unit   = string
    use_case_name   = string
    environment     = string
  })
}

variable "api_name_mapping" {
  description = "Map of service code → list of API names already deployed in APIM."
  type        = map(list(string))
}

variable "services" {
  description = "Services onboarded for this use-case."
  type = list(object({
    code                   = string
    endpoint_secret_name   = string
    api_key_secret_name    = string
    policy_xml             = optional(string, "")
  }))
}

variable "product_terms" {
  description = "Product terms shown to subscribers."
  type        = string
  default     = ""
}

# -- Key Vault output (optional) -----------------------------------------------

variable "use_target_key_vault" {
  description = "If true, write endpoints + keys into Key Vault instead of returning them as outputs."
  type        = bool
  default     = true
}

variable "key_vault_id" {
  description = "Target Key Vault resource ID (required when use_target_key_vault = true)."
  type        = string
  default     = ""
}

# -- Foundry connection (optional) ---------------------------------------------

variable "use_target_foundry" {
  description = "If true, create a Foundry-project → APIM connection per service."
  type        = bool
  default     = false
}

variable "foundry_project_id" {
  description = "Target Foundry project resource ID."
  type        = string
  default     = ""
}

variable "foundry_connection_name_prefix" {
  description = "Prefix used in Foundry connection names (falls back to use-case postfix)."
  type        = string
  default     = ""
}

variable "foundry_is_shared_to_all" { 
    type = bool 
    default = false 
}
variable "foundry_deployment_in_path" { 
    type = string
    default = "false"
}
variable "foundry_inference_api_version" { 
    type = string
    default = ""
}
variable "foundry_deployment_api_version" { 
    type = string
    default = ""
}
variable "foundry_static_models" { 
    type = list(any)
    default = []
}
variable "foundry_custom_headers" { 
    type = map(string)
    default = {}
}

# Bicep parity: foundryConnection.bicep connectionCategory
# (@allowed(['ApiManagement','ModelGateway'])).
variable "foundry_connection_category" {
  type    = string
  default = "ApiManagement"
  validation {
    condition     = contains(["ApiManagement", "ModelGateway"], var.foundry_connection_category)
    error_message = "foundry_connection_category must be ApiManagement or ModelGateway."
  }
}
