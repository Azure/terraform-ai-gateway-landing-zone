# Shared by every stack (variables.common.tf).
workload        = "aigw"
environment     = "prod"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "byo"

# The APIM service, its resource group and its managed identity already exist:
# point the naming contract (modules/naming) at them instead of the generated names.
naming = {
  name_overrides = {
    resource_group = "<existing-apim-resource-group>"
    apim           = "<existing-apim-name>"
    uami_apim      = "<existing-apim-user-assigned-identity>"
  }
}

tags = {
  Workload    = "ai-gateway",
  Environment = "prod",
  CostCenter  = "tbd",
  Project     = "tbd",
  Owner       = "tbd"
}
