# Shared by every stack (variables.common.tf).
workload        = "aigw"
environment     = "dev"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "greenfield"
tags = {
  Workload        = "ai-gateway",
  Environment     = "dev",
  SecurityControl = "ignore",
  CostCenter      = "tbd",
  Project         = "tbd",
  Owner           = "tbd"
}
