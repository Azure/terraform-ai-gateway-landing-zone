# Shared by every stack (variables.common.tf).
workload        = "aigw"
environment     = "test"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "byo"
tags            = { workload = "ai-gateway", environment = "test" }
