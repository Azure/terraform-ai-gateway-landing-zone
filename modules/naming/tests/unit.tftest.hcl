# Snapshot test: fixed inputs => fixed names. A failure means an update would
# rename (and replace) resources of an existing environment.
variables {
  environment_name       = "citadel-dev"
  resource_group_name    = "rg-citadel-dev"
  subscription_id        = "00000000-0000-0000-0000-000000000000"
  foundry_instance_names = ["", "my-foundry"]
}

run "snapshot" {
  command = plan

  assert {
    condition = output.names == {
      resource_group          = "rg-citadel-dev"
      apim                    = "apim-${substr(sha256("rg-citadel-dev-citadel-dev-00000000-0000-0000-0000-000000000000"), 0, 10)}"
      cosmos                  = "cosmos-${substr(sha256("rg-citadel-dev-citadel-dev-00000000-0000-0000-0000-000000000000"), 0, 10)}"
      eventhub_namespace      = "evhns-${substr(sha256("rg-citadel-dev-citadel-dev-00000000-0000-0000-0000-000000000000"), 0, 10)}"
      log_analytics           = "law-${substr(sha256("rg-citadel-dev-citadel-dev-00000000-0000-0000-0000-000000000000"), 0, 10)}"
      key_vault               = "kv-${substr(sha256("rg-citadel-dev-citadel-dev-00000000-0000-0000-0000-000000000000"), 0, 10)}"
      virtual_network         = "vnet-citadel-dev"
      uami_apim               = "id-apim-citadel-dev-20ebd0"
      uami_usage              = "id-logicapp-citadel-dev-20ebd0"
      redis                   = "redis-citadel-dev-20ebd0"
      api_center              = "apic-citadel-dev-20ebd0"
      storage_logic           = "stla20ebd0"
      logic_app               = "logic-usage-citadel-dev-20ebd0"
      logic_content_share     = "logic-content-20ebd0"
      app_service_plan        = "asp-logic-citadel-dev"
      app_service_environment = "ase-citadel-dev-20ebd0"
      logic_app_code_artifact = "usage-ingestion-logicapp-20ebd0"
    }
    error_message = "The naming contract changed: an update would rename (replace) resources."
  }
  assert {
    condition     = output.foundry_account_names == ["aif-citadel-dev-0-20ebd0", "my-foundry"]
    error_message = "Foundry names must be aif-<env>-<index>-<suffix> unless an explicit name is given."
  }
}

run "overrides_win" {
  command = plan
  variables {
    name_overrides = { apim = "apim-custom", key_vault = "", redis = null }
  }
  assert {
    condition     = output.names.apim == "apim-custom" && startswith(output.names.key_vault, "kv-") && output.names.redis == "redis-citadel-dev-20ebd0"
    error_message = "Non-empty overrides must win; empty / null overrides must be ignored."
  }
}
