# =============================================================================
# modules/apim preconditions (WP-1.6): the SKU x network matrix and scale rules.
#   terraform init -backend=false && terraform test -test-directory=tests/unit
# =============================================================================

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      client_id       = "00000000-0000-0000-0000-000000000004"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      tenant_id       = "00000000-0000-0000-0000-000000000001"
    }
  }
}

mock_provider "azurerm" {
  alias           = "loganalytics"
  override_during = plan
}

mock_provider "azapi" {
  override_during = plan
}
mock_provider "azuread" {
  override_during = plan
}
mock_provider "random" {
  override_during = plan
}
mock_provider "time" {
  override_during = plan
}
mock_provider "archive" {
  override_during = plan
}
mock_provider "null" {
  override_during = plan
}
mock_provider "http" {
  override_during = plan
}

variables {
  resource_group_name           = "rg-citadel-test"
  location                      = "swedencentral"
  tags                          = {}
  apim_name                     = "apim-test"
  sku_name                      = "StandardV2"
  sku_capacity                  = 1
  publisher_email               = "admin@contoso.com"
  publisher_name                = "Test"
  apim_network_type             = "None"
  is_apim_v2                    = true
  apim_subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/apim"
  pe_subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
  vnet_id                       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  apim_v2_use_private_endpoint  = true
  apim_v2_public_network_access = true
  managed_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-apim"
  managed_identity_client_id    = "00000000-0000-0000-0000-000000000009"
  dns_zone_id_apim              = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
  pii_service_endpoint          = ""
  content_safety_endpoint       = ""
  enable_pii_redaction          = false
  enable_content_safety         = false
  entra_auth_enabled            = false
  entra_tenant_id               = ""
  entra_client_id               = ""
  entra_audience                = ""
  subscription_id               = "00000000-0000-0000-0000-000000000002"
  default_product_api_names     = { universal_llm = "universal-llm-api", azure_openai = "azure-openai-api" }
}

run "v2_defaults_are_valid" {
  command = plan
  module {
    source = "./modules/apim"
  }
}

run "v2_private_access_needs_private_endpoint" {
  command = plan
  module {
    source = "./modules/apim"
  }
  variables {
    apim_v2_use_private_endpoint  = false
    apim_v2_public_network_access = false
  }
  expect_failures = [terraform_data.service_rules]
}


run "zones_need_premium_and_enough_units" {
  command = plan
  module {
    source = "./modules/apim"
  }
  variables {
    sku_name          = "Premium"
    is_apim_v2        = false
    apim_network_type = "External"
    sku_capacity      = 2
    apim_zones        = ["1", "2", "3"]
  }
  expect_failures = [terraform_data.service_rules]
}

run "premium_zone_redundant_is_valid" {
  command = plan
  module {
    source = "./modules/apim"
  }
  variables {
    sku_name          = "Premium"
    is_apim_v2        = false
    apim_network_type = "Internal"
    sku_capacity      = 3
    apim_zones        = ["1", "2", "3"]
  }
}
