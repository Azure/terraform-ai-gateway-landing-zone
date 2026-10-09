# Snapshot test: fixed inputs => fixed names. Every stack depends on these
# names to find what other stacks own, so a failure here is a breaking change.
variables {
  workload               = "aigw"
  environment            = "dev"
  subscription_id        = "00000000-0000-0000-0000-000000000000"
  foundry_instance_names = ["", "my-foundry"]
}

run "snapshot" {
  command = plan

  assert {
    condition = output.names == {
      resource_group          = "rg-aigw-dev"
      state_resource_group    = "rg-aigw-dev-tfstate"
      state_storage_account   = "staigwdev27cbbtf"
      pipeline_plan           = "id-tf-aigw-dev-plan"
      pipeline_apply          = "id-tf-aigw-dev-apply"
      gateway_app             = "app-aigw-dev-27cbb-gateway"
      virtual_network         = "vnet-aigw-dev"
      subnet_apim             = "snet-apim"
      subnet_pe               = "snet-pe"
      subnet_logic_app        = "snet-logic"
      subnet_agent            = "snet-agent"
      subnet_ase              = "snet-ase"
      subnet_cicd             = "snet-cicd"
      app_service_environment = "ase-aigw-dev-27cbb"
      apim                    = "apim-aigw-dev-27cbb"
      key_vault               = "kv-aigw-dev-27cbb"
      cosmos                  = "cosno-aigw-dev-27cbb"
      eventhub_namespace      = "evhns-aigw-dev-27cbb"
      log_analytics           = "log-aigw-dev"
      uami_apim               = "id-aigw-dev-apim"
      uami_usage              = "id-aigw-dev-usage"
      redis                   = "redis-aigw-dev-27cbb"
      api_center              = "apic-aigw-dev-27cbb"
      language_service        = "lang-aigw-dev-27cbb"
      content_safety          = "cs-aigw-dev-27cbb"
      storage_logic           = "staigwdev27cbb"
      logic_app               = "logic-aigw-dev-27cbb"
      logic_content_share     = "logic-content-27cbb"
      app_service_plan        = "asp-aigw-dev"
      logic_app_code_artifact = "usage-ingestion-logicapp-27cbb"
    }
    error_message = "The naming contract changed: stacks would no longer find each other's resources."
  }
  assert {
    condition     = output.foundry_account_names == ["aif-aigw-dev-27cbb-0", "my-foundry"]
    error_message = "Foundry names must be aif-<workload>-<environment>-<seed>-<index> unless an explicit name is given."
  }
}

run "private_dns_zones" {
  command = plan

  assert {
    condition     = length(output.private_dns_zones) == 13 && !contains(keys(output.private_dns_zones), "logic_app")
    error_message = "The 13 base zones don't include the optional Logic App zone."
  }
  assert {
    condition     = output.private_dns_optional_zones == { logic_app = "privatelink.azurewebsites.net" }
    error_message = "The Logic App private endpoint zone is the only optional zone."
  }
}

run "length_limits" {
  command = plan
  variables {
    workload    = "abcdefgh"
    environment = "quickstart"
  }
  assert {
    condition = alltrue([
      length(output.names.key_vault) <= 24,
      length(output.names.storage_logic) <= 24,
      length(output.names.state_storage_account) <= 24,
      can(regex("^[a-z0-9]+$", output.names.storage_logic)),
      can(regex("^[a-z0-9]+$", output.names.state_storage_account)),
    ])
    error_message = "Key Vault and storage account names must fit their 24-character limits."
  }
}

run "seed_and_overrides" {
  command = plan
  variables {
    unique_seed    = "k3x9p"
    name_overrides = { apim = "apim-custom", key_vault = "", redis = null }
  }
  assert {
    condition     = output.names.apim == "apim-custom" && output.names.key_vault == "kv-aigw-dev-k3x9p" && output.names.redis == "redis-aigw-dev-k3x9p"
    error_message = "unique_seed must replace the derived seed; non-empty overrides must win; empty / null overrides must be ignored."
  }
}
