# Shared by every stack (variables.common.tf).
workload        = "aigw"
environment     = "test"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "greenfield"
tags = {
  Workload    = "ai-gateway",
  Environment = "test",
  CostCenter  = "tbd",
  Project     = "tbd",
  Owner       = "tbd"
}
