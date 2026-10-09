# Unit tests (mocked azapi, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azapi" {
  override_during = plan
}

variables {
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
  tags              = {}
  enable_api_center = true
  api_center_sku    = "Free"
  apic_location     = "swedencentral"
  api_center_name   = "apic-aigw-dev"
}

run "no_remote_mcp_servers_by_default" {
  command = plan

  assert {
    condition     = length(azapi_resource.api_center_mcp_api) == 0 && length(azapi_resource.api_center_mcp_deployment) == 0
    error_message = "Nothing is catalogued unless remote_mcp_servers is set."
  }
  assert {
    condition     = length(azapi_resource.api_center_metadata_schema) == 7
    error_message = "The seven metadata schemas of apic-metadata.json are created."
  }
}

run "remote_mcp_servers_are_catalogued" {
  command = plan

  variables {
    remote_mcp_servers = [
      { name = "microsoft-learn", description = "Microsoft Learn search", url = "https://learn.microsoft.com/api/mcp", documentation_url = "https://learn.microsoft.com/training/support/mcp" },
      { name = "partner-tools", description = "Partner tools", url = "https://mcp.partner.example.com/sse" },
    ]
  }

  assert {
    condition     = sort(keys(azapi_resource.api_center_mcp_api)) == tolist(["microsoft-learn", "partner-tools"]) && length(azapi_resource.api_center_mcp_version) == 2 && length(azapi_resource.api_center_mcp_definition) == 2 && length(azapi_resource.api_center_mcp_deployment) == 2
    error_message = "Each server gets an API, a version, a definition and a deployment."
  }
  assert {
    condition     = azapi_resource.api_center_mcp_api["microsoft-learn"].body.properties.title == "Microsoft-learn" && azapi_resource.api_center_mcp_api["microsoft-learn"].body.properties.kind == "mcp" && azapi_resource.api_center_mcp_version["microsoft-learn"].body.properties.lifecycleStage == "development"
    error_message = "The API is of kind mcp, titled after its name; kind and lifecycle stage are lowercase because API Center stores them that way (any other casing is a permanent diff)."
  }
  assert {
    condition     = azapi_resource.api_center_mcp_deployment["partner-tools"].body.properties.server.runtimeUri[0] == "https://mcp.partner.example.com/sse"
    error_message = "The deployment's runtime URI is the server's URL."
  }
  assert {
    condition     = length(azapi_resource.api_center_mcp_api["microsoft-learn"].body.properties.externalDocumentation) == 2 && length(azapi_resource.api_center_mcp_api["partner-tools"].body.properties.externalDocumentation) == 1
    error_message = "The documentation link is added only when given."
  }
}

run "nothing_is_catalogued_when_api_center_is_off" {
  command = plan

  variables {
    enable_api_center  = false
    remote_mcp_servers = [{ name = "partner-tools", description = "Partner tools", url = "https://mcp.partner.example.com/sse" }]
  }

  assert {
    condition     = length(azapi_resource.api_center_mcp_api) == 0 && output.api_center_id == ""
    error_message = "enable_api_center = false creates nothing."
  }
}

run "server_names_must_be_unique" {
  command = plan

  variables {
    remote_mcp_servers = [
      { name = "a", description = "x", url = "https://x.example.com" },
      { name = "a", description = "y", url = "https://y.example.com" },
    ]
  }

  expect_failures = [var.remote_mcp_servers]
}

run "server_names_are_validated" {
  command = plan

  variables {
    remote_mcp_servers = [{ name = "not a name", description = "x", url = "https://x.example.com" }]
  }

  expect_failures = [var.remote_mcp_servers]
}

run "server_urls_are_validated" {
  command = plan

  variables {
    remote_mcp_servers = [{ name = "partner", description = "x", url = "ftp://x.example.com" }]
  }

  expect_failures = [var.remote_mcp_servers]
}

run "server_urls_cannot_break_out_of_the_install_link" {
  command = plan

  variables {
    remote_mcp_servers = [{ name = "partner", description = "x", url = "https://x.example.com/\"}" }]
  }

  expect_failures = [var.remote_mcp_servers]
}
