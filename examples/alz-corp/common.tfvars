# Shared by every stack (variables.common.tf).
workload        = "aigw"
environment     = "prod"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "alz_spoke"
tags            = { workload = "ai-gateway", environment = "prod" }
