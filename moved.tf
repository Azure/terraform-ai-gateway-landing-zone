# =============================================================================
# REFACTORING HISTORY — `moved` blocks keep state addresses stable when code
# moves between modules (Phase 1 of the implementation plan). Keep them for at
# least one major release so every existing deployment has applied them.
# =============================================================================

# WP-1.2: API Center registration moved out of modules/apim
moved {
  from = module.apim.azapi_resource.apic_api
  to   = module.api_center_registration.azapi_resource.apic_api
}
moved {
  from = module.apim.azapi_resource.apic_api_version
  to   = module.api_center_registration.azapi_resource.apic_api_version
}
moved {
  from = module.apim.azapi_resource.apic_api_definition
  to   = module.api_center_registration.azapi_resource.apic_api_definition
}
moved {
  from = module.apim.azapi_resource.apic_api_deployment
  to   = module.api_center_registration.azapi_resource.apic_api_deployment
}

# WP-1.2: LLM backends, pools and generated routing fragments -> modules/llm-routing
moved {
  from = module.apim.azapi_resource.llm_backend
  to   = module.llm_routing.azapi_resource.llm_backend
}
moved {
  from = module.apim.azapi_resource.llm_backend_pool
  to   = module.llm_routing.azapi_resource.llm_backend_pool
}
moved {
  from = module.apim.azurerm_api_management_policy_fragment.set_backend_pools
  to   = module.llm_routing.azurerm_api_management_policy_fragment.set_backend_pools
}
moved {
  from = module.apim.azurerm_api_management_policy_fragment.get_available_models
  to   = module.llm_routing.azurerm_api_management_policy_fragment.get_available_models
}
moved {
  from = module.apim.azurerm_api_management_policy_fragment.metadata_config
  to   = module.llm_routing.azurerm_api_management_policy_fragment.metadata_config
}
moved {
  from = module.apim.azurerm_api_management_policy_fragment.resolve_model_alias
  to   = module.llm_routing.azurerm_api_management_policy_fragment.resolve_model_alias
}

# WP-1.2: shared policy fragments -> modules/apim-policy-fragments
moved {
  from = module.apim.azurerm_api_management_policy_fragment.static
  to   = module.policy_fragments.azurerm_api_management_policy_fragment.this
}
moved {
  from = module.apim.azapi_resource.pii_fragment
  to   = module.policy_fragments.azapi_resource.this
}

# WP-1.2: loggers and service-level diagnostics -> modules/apim-telemetry
moved {
  from = module.apim.azurerm_api_management_logger.app_insights
  to   = module.apim_telemetry.azurerm_api_management_logger.app_insights
}
moved {
  from = module.apim.terraform_data.azure_monitor_logger_posix
  to   = module.apim_telemetry.terraform_data.azure_monitor_logger_posix
}
moved {
  from = module.apim.terraform_data.azure_monitor_logger_windows
  to   = module.apim_telemetry.terraform_data.azure_monitor_logger_windows
}
moved {
  from = module.apim.azurerm_api_management_logger.eventhub
  to   = module.apim_telemetry.azurerm_api_management_logger.eventhub
}
moved {
  from = module.apim.azurerm_api_management_logger.pii_eventhub
  to   = module.apim_telemetry.azurerm_api_management_logger.pii_eventhub
}
moved {
  from = module.apim.azurerm_api_management_diagnostic.global
  to   = module.apim_telemetry.azurerm_api_management_diagnostic.global
}
moved {
  from = module.apim.azapi_update_resource.global_appinsights_metrics
  to   = module.apim_telemetry.azapi_update_resource.global_appinsights_metrics
}
moved {
  from = module.apim.azapi_resource_action.apim_diagnostics
  to   = module.apim_telemetry.azapi_resource_action.apim_diagnostics
}

# WP-1.2: APIs -> modules/gateway-api (module.api / module.api_dependent, root apis.tf)
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api.this
  to   = module.api["universal-llm-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_policy.this
  to   = module.api["universal-llm-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_operation_policy.deployments[0]
  to   = module.api["universal-llm-api"].azurerm_api_management_api_operation_policy.this["deployments"]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_operation_policy.deployment_by_name[0]
  to   = module.api["universal-llm-api"].azurerm_api_management_api_operation_policy.this["deployment-by-name"]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_diagnostic.app_insights
  to   = module.api["universal-llm-api"].azurerm_api_management_api_diagnostic.app_insights[0]
}
moved {
  from = module.apim.module.universal_llm.azapi_update_resource.app_insights_metrics
  to   = module.api["universal-llm-api"].azapi_update_resource.app_insights_metrics[0]
}
moved {
  from = module.apim.module.universal_llm.azapi_resource.azure_monitor_diagnostic
  to   = module.api["universal-llm-api"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_operation_policy.list_models[0]
  to   = module.api["universal-llm-api"].azurerm_api_management_api_operation_policy.this["listModels"]
}
moved {
  from = module.apim.module.universal_llm.azurerm_api_management_api_operation_policy.retrieve_model[0]
  to   = module.api["universal-llm-api"].azurerm_api_management_api_operation_policy.this["retrieveModel"]
}
moved {
  from = module.apim.module.azure_openai.azurerm_api_management_api.this
  to   = module.api["azure-openai-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.module.azure_openai.azurerm_api_management_api_policy.this
  to   = module.api["azure-openai-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.module.azure_openai.azurerm_api_management_api_operation_policy.deployments[0]
  to   = module.api["azure-openai-api"].azurerm_api_management_api_operation_policy.this["deployments"]
}
moved {
  from = module.apim.module.azure_openai.azurerm_api_management_api_operation_policy.deployment_by_name[0]
  to   = module.api["azure-openai-api"].azurerm_api_management_api_operation_policy.this["deployment-by-name"]
}
moved {
  from = module.apim.module.azure_openai.azurerm_api_management_api_diagnostic.app_insights
  to   = module.api["azure-openai-api"].azurerm_api_management_api_diagnostic.app_insights[0]
}
moved {
  from = module.apim.module.azure_openai.azapi_update_resource.app_insights_metrics
  to   = module.api["azure-openai-api"].azapi_update_resource.app_insights_metrics[0]
}
moved {
  from = module.apim.module.azure_openai.azapi_resource.azure_monitor_diagnostic
  to   = module.api["azure-openai-api"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.module.unified_ai[0].azurerm_api_management_api.this
  to   = module.api["unified-ai-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.module.unified_ai[0].azurerm_api_management_api_policy.this
  to   = module.api["unified-ai-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.module.unified_ai[0].azurerm_api_management_product.this
  to   = module.api["unified-ai-api"].azurerm_api_management_product.this[0]
}
moved {
  from = module.apim.module.unified_ai[0].azurerm_api_management_product_api.this
  to   = module.api["unified-ai-api"].azurerm_api_management_product_api.this[0]
}
moved {
  from = module.apim.module.unified_ai[0].azurerm_api_management_product_policy.this
  to   = module.api["unified-ai-api"].azurerm_api_management_product_policy.this[0]
}
moved {
  from = module.apim.module.unified_ai[0].azapi_resource.deployments_policy
  to   = module.api["unified-ai-api"].azapi_resource.operation_policy["deployments"]
}
moved {
  from = module.apim.module.unified_ai[0].azapi_resource.deployment_by_name_policy
  to   = module.api["unified-ai-api"].azapi_resource.operation_policy["deployment-by-name"]
}
moved {
  from = module.apim.module.unified_ai[0].azapi_resource.azure_monitor_diagnostic
  to   = module.api["unified-ai-api"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.azurerm_api_management_api.ai_search[0]
  to   = module.api["azure-ai-search-index-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_policy.ai_search[0]
  to   = module.api["azure-ai-search-index-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_diagnostic.ai_search_appinsights[0]
  to   = module.api["azure-ai-search-index-api"].azurerm_api_management_api_diagnostic.app_insights[0]
}
moved {
  from = module.apim.azapi_update_resource.ai_search_appinsights_metrics[0]
  to   = module.api["azure-ai-search-index-api"].azapi_update_resource.app_insights_metrics[0]
}
moved {
  from = module.apim.azapi_resource.ai_search_azuremonitor[0]
  to   = module.api["azure-ai-search-index-api"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.azurerm_api_management_api.doc_intelligence_legacy[0]
  to   = module.api["document-intelligence-api-legacy"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_policy.doc_intelligence_legacy[0]
  to   = module.api["document-intelligence-api-legacy"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_diagnostic.doc_intelligence_legacy_appinsights[0]
  to   = module.api["document-intelligence-api-legacy"].azurerm_api_management_api_diagnostic.app_insights[0]
}
moved {
  from = module.apim.azapi_update_resource.doc_intelligence_legacy_appinsights_metrics[0]
  to   = module.api["document-intelligence-api-legacy"].azapi_update_resource.app_insights_metrics[0]
}
moved {
  from = module.apim.azapi_resource.doc_intelligence_legacy_azuremonitor[0]
  to   = module.api["document-intelligence-api-legacy"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.azurerm_api_management_api.doc_intelligence[0]
  to   = module.api_dependent["document-intelligence-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_policy.doc_intelligence[0]
  to   = module.api_dependent["document-intelligence-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_diagnostic.doc_intelligence_appinsights[0]
  to   = module.api_dependent["document-intelligence-api"].azurerm_api_management_api_diagnostic.app_insights[0]
}
moved {
  from = module.apim.azapi_update_resource.doc_intelligence_appinsights_metrics[0]
  to   = module.api_dependent["document-intelligence-api"].azapi_update_resource.app_insights_metrics[0]
}
moved {
  from = module.apim.azapi_resource.doc_intelligence_azuremonitor[0]
  to   = module.api_dependent["document-intelligence-api"].azapi_resource.azure_monitor_diagnostic[0]
}
moved {
  from = module.apim.azurerm_api_management_api.ai_model_inference[0]
  to   = module.api["ai-model-inference-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_policy.ai_model_inference[0]
  to   = module.api["ai-model-inference-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api.weather[0]
  to   = module.api["weather-api"].azurerm_api_management_api.this[0]
}
moved {
  from = module.apim.azurerm_api_management_api_policy.weather[0]
  to   = module.api["weather-api"].azurerm_api_management_api_policy.this[0]
}
moved {
  from = module.apim.azapi_resource.openai_realtime[0]
  to   = module.api["openai-realtime-ws-api"].azapi_resource.this[0]
}
moved {
  from = module.apim.azapi_resource.weather_mcp[0]
  to   = module.api_dependent["weather-mcp"].azapi_resource.this[0]
}
moved {
  from = module.apim.azapi_resource.weather_mcp_policy[0]
  to   = module.api_dependent["weather-mcp"].azapi_resource.policy[0]
}
moved {
  from = module.apim.azapi_resource.ms_learn_mcp[0]
  to   = module.api_dependent["ms-learn-mcp"].azapi_resource.this[0]
}
moved {
  from = module.apim.azapi_resource.ms_learn_mcp_policy[0]
  to   = module.api_dependent["ms-learn-mcp"].azapi_resource.policy[0]
}

# --- WP-1.4: networking is greenfield-only (count on the module call); private DNS moved to modules/private-dns ---
moved {
  from = module.networking.azurerm_virtual_network.citadel[0]
  to   = module.networking[0].azurerm_virtual_network.citadel
}
moved {
  from = module.networking.azurerm_network_security_group.agent
  to   = module.networking[0].azurerm_network_security_group.agent
}
moved {
  from = module.networking.azurerm_network_security_group.apim[0]
  to   = module.networking[0].azurerm_network_security_group.apim
}
moved {
  from = module.networking.azurerm_route_table.apim
  to   = module.networking[0].azurerm_route_table.apim
}
moved {
  from = module.networking.azurerm_subnet.apim[0]
  to   = module.networking[0].azurerm_subnet.apim
}
moved {
  from = module.networking.azurerm_subnet_network_security_group_association.apim[0]
  to   = module.networking[0].azurerm_subnet_network_security_group_association.apim
}
moved {
  from = module.networking.azurerm_subnet_route_table_association.apim
  to   = module.networking[0].azurerm_subnet_route_table_association.apim
}
moved {
  from = module.networking.azurerm_subnet.pe[0]
  to   = module.networking[0].azurerm_subnet.pe
}
moved {
  from = module.networking.azurerm_subnet.logic_app[0]
  to   = module.networking[0].azurerm_subnet.logic_app
}
moved {
  from = module.networking.azurerm_subnet.agent
  to   = module.networking[0].azurerm_subnet.agent
}
moved {
  from = module.networking.azurerm_subnet_network_security_group_association.agent
  to   = module.networking[0].azurerm_subnet_network_security_group_association.agent
}
moved {
  from = module.networking.azurerm_subnet.ase
  to   = module.networking[0].azurerm_subnet.ase
}
moved {
  from = module.networking.azurerm_network_security_group.ase
  to   = module.networking[0].azurerm_network_security_group.ase
}
moved {
  from = module.networking.azurerm_subnet_network_security_group_association.ase
  to   = module.networking[0].azurerm_subnet_network_security_group_association.ase
}
moved {
  from = module.networking.azurerm_network_security_group.pe
  to   = module.networking[0].azurerm_network_security_group.pe
}
moved {
  from = module.networking.azurerm_subnet_network_security_group_association.pe
  to   = module.networking[0].azurerm_subnet_network_security_group_association.pe
}
moved {
  from = module.networking.azurerm_network_security_group.logic_app
  to   = module.networking[0].azurerm_network_security_group.logic_app
}
moved {
  from = module.networking.azurerm_subnet_network_security_group_association.logic_app
  to   = module.networking[0].azurerm_subnet_network_security_group_association.logic_app
}
moved {
  from = module.networking.azurerm_private_dns_zone.zones
  to   = module.private_dns.azurerm_private_dns_zone.zones
}
moved {
  from = module.networking.azurerm_private_dns_zone_virtual_network_link.links
  to   = module.private_dns.azurerm_private_dns_zone_virtual_network_link.links
}

# --- WP-2.1: identities, Log Analytics and App Insights on Azure Verified Modules ---
moved {
  from = azurerm_user_assigned_identity.apim
  to   = module.identity["apim"].azurerm_user_assigned_identity.this
}
moved {
  from = azurerm_user_assigned_identity.usage
  to   = module.identity["usage"].azurerm_user_assigned_identity.this
}
moved {
  from = module.monitoring.azurerm_log_analytics_workspace.citadel[0]
  to   = module.monitoring.module.log_analytics[0].azurerm_log_analytics_workspace.this
}
moved {
  from = module.monitoring.azurerm_application_insights.apim
  to   = module.monitoring.module.app_insights["apim"].azurerm_application_insights.this
}
moved {
  from = module.monitoring.azurerm_application_insights.logic_app
  to   = module.monitoring.module.app_insights["logic_app"].azurerm_application_insights.this
}
moved {
  from = module.monitoring.azurerm_application_insights.foundry
  to   = module.monitoring.module.app_insights["foundry"].azurerm_application_insights.this
}

# --- WP-2.2: Key Vault on the Azure Verified Module ---
moved {
  from = module.security.azurerm_key_vault.citadel
  to   = module.security.module.key_vault.azurerm_key_vault.this
}
moved {
  from = module.security.azurerm_role_assignment.deployer_kv_admin
  to   = module.security.module.key_vault.azurerm_role_assignment.this["deployer_kv_admin"]
}
moved {
  from = module.security.azurerm_role_assignment.uami_kv_secrets_user
  to   = module.security.module.key_vault.azurerm_role_assignment.this["uami_kv_secrets_user"]
}
moved {
  from = module.security.azurerm_private_endpoint.key_vault
  to   = module.security.module.key_vault.azurerm_private_endpoint.this["vault"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[0]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_0"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[1]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_1"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[2]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_2"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[3]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_3"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[4]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_4"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[5]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_5"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[6]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_6"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[7]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_7"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[8]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_8"]
}
moved {
  from = module.security.azurerm_role_assignment.foundry_kv_secrets_user[9]
  to   = module.security.module.key_vault.azurerm_role_assignment.this["foundry_kv_secrets_user_9"]
}

# --- WP-2.4: Cosmos DB on the Azure Verified Module ---
moved {
  from = module.cosmosdb.azurerm_cosmosdb_account.citadel
  to   = module.cosmosdb.module.cosmos.azurerm_cosmosdb_account.this
}
moved {
  from = module.cosmosdb.azurerm_cosmosdb_sql_database.usage
  to   = module.cosmosdb.module.cosmos.azurerm_cosmosdb_sql_database.this["usage"]
}
moved {
  from = module.cosmosdb.azurerm_private_endpoint.cosmos
  to   = module.cosmosdb.module.cosmos.azurerm_private_endpoint.this_managed_dns_zone_groups["sql"]
}

# --- WP-2.5: Event Hub namespace, hubs, RBAC and PE on the Azure Verified Module ---
moved {
  from = module.eventhub.azurerm_eventhub_namespace.citadel
  to   = module.eventhub.module.namespace.azurerm_eventhub_namespace.this[0]
}
moved {
  from = module.eventhub.azurerm_eventhub.ai_usage
  to   = module.eventhub.module.namespace.azurerm_eventhub.this["ai-usage"]
}
moved {
  from = module.eventhub.azurerm_eventhub.pii_usage
  to   = module.eventhub.module.namespace.azurerm_eventhub.this["pii-usage"]
}
moved {
  from = module.eventhub.azurerm_private_endpoint.eventhub
  to   = module.eventhub.module.namespace.azurerm_private_endpoint.this["namespace"]
}
moved {
  from = module.eventhub.azurerm_role_assignment.eventhub_data_sender
  to   = module.eventhub.module.namespace.azurerm_role_assignment.this["apim_data_sender"]
}
moved {
  from = module.eventhub.azurerm_role_assignment.eventhub_data_receiver
  to   = module.eventhub.module.namespace.azurerm_role_assignment.this["usage_data_receiver"]
}
moved {
  from = module.eventhub.azurerm_role_assignment.eventhub_data_owner_usage
  to   = module.eventhub.module.namespace.azurerm_role_assignment.this["usage_data_owner"]
}
