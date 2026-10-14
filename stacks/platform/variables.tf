# =============================================================================
# Platform inputs. Network IDs: greenfield looks them up by name (network-lookup.tf);
# alz_spoke / byo pass the `network` object.
# =============================================================================

variable "apim" {
  description = <<-EOT
    API Management settings (network matrix: review 7.5.4.1).
      sku                   Developer | Premium | StandardV2 | PremiumV2.
      capacity              Scale units.
      vnet_mode             none         no VNet (public endpoint and/or inbound private endpoint).
                            external     Developer/Premium: classic injection, public VIP.
                            internal     Developer/Premium: classic injection, private VIP.
                            integration  StandardV2/PremiumV2: outbound VNet integration
                                         (subnet delegated to Microsoft.Web/serverFarms).
                            injection    PremiumV2: VNet injection, private VIP (subnet
                                         delegated to Microsoft.Web/hostingEnvironments, >= /27).
                            null = external for classic SKUs, integration for v2 SKUs.
      private_endpoint      Inbound private endpoint (v2 SKUs with vnet_mode none or integration).
      public_network_access Public inbound access (v2 SKUs). false needs the private endpoint;
                            a new service is created public and switched on the next apply.
      public_ip_address_id  Classic external/internal only: Standard-SKU public IP to use.
      zone_redundant        Spread the gateway over availability zones (region must support them).
                            StandardV2 / PremiumV2: set at creation only (Azure can't change it on an
                            existing instance); 2+ units recommended so a zone loss keeps capacity.
                            Premium (classic): automatic with capacity >= 2 (zones 1-2 for 2 units,
                            1-3 for 3+), whatever this flag says; true requires capacity >= 2.
                            Developer: no zones.
  EOT
  type = object({
    sku                   = optional(string, "StandardV2")
    capacity              = optional(number, 1)
    publisher_email       = optional(string, "admin@contoso.com")
    publisher_name        = optional(string, "AI Citadel Admin")
    vnet_mode             = optional(string)
    private_endpoint      = optional(bool, true)
    public_network_access = optional(bool, true)
    public_ip_address_id  = optional(string)
    zone_redundant        = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Developer", "Premium", "StandardV2", "PremiumV2"], var.apim.sku)
    error_message = "apim.sku must be Developer, Premium, StandardV2 or PremiumV2."
  }
  validation {
    condition = var.apim.vnet_mode == null || contains(lookup({
      Developer  = ["none", "external", "internal"]
      Premium    = ["none", "external", "internal"]
      StandardV2 = ["none", "integration"]
      PremiumV2  = ["none", "integration", "injection"]
    }, var.apim.sku, []), coalesce(var.apim.vnet_mode, "-"))
    error_message = "apim.vnet_mode isn't supported for this SKU: Developer/Premium take none, external or internal; StandardV2 takes none or integration; PremiumV2 takes none, integration or injection."
  }
  validation {
    condition     = var.apim.public_network_access || (var.apim.private_endpoint && contains(["StandardV2", "PremiumV2"], var.apim.sku) && contains(["none", "integration"], coalesce(var.apim.vnet_mode, "integration")))
    error_message = "apim.public_network_access = false needs the inbound private endpoint: a v2 SKU, private_endpoint = true and vnet_mode none or integration."
  }
  validation {
    condition     = var.apim.public_ip_address_id == null || contains(["external", "internal"], coalesce(var.apim.vnet_mode, contains(["Developer", "Premium"], var.apim.sku) ? "external" : "integration"))
    error_message = "apim.public_ip_address_id applies only to classic external/internal injection."
  }
  validation {
    condition     = var.apim.sku != "Developer" || var.apim.capacity == 1
    error_message = "The Developer SKU can't scale out: apim.capacity must be 1."
  }
  validation {
    condition     = !var.apim.zone_redundant || contains(["StandardV2", "PremiumV2"], var.apim.sku) || (var.apim.sku == "Premium" && var.apim.capacity >= 2)
    error_message = "apim.zone_redundant: the Developer SKU has no availability zones; classic Premium needs apim.capacity >= 2 (its units are spread over the zones)."
  }
}

variable "network" {
  description = <<-EOT
    alz_spoke / byo only (greenfield: null, everything is looked up by name).
      vnet_id                            VNet that holds the subnets.
      subnet_ids.pe                      Private endpoint subnet.
      subnet_ids.apim                    APIM subnet (apim.vnet_mode != none).
      subnet_ids.logic_app               Logic App subnet (usage_pipeline.logic_app.hosting = workflow_standard).
      subnet_ids.agent                   Foundry agent subnet (foundry.network_injection_enabled).
      private_dns_zone_ids               Logical key (modules/naming private_dns_zones) => hub zone ID.
                                         Keys Terraform must bind even under policy: openai, ai_services,
                                         apim_gateway, redis.
      dns_zone_groups_managed_by_policy  Azure Policy (ALZ Deploy-Private-DNS-Zones) creates the private
                                         endpoint DNS zone groups; Terraform leaves them alone.
    `task output STACK=network NAME=platform_network` prints this object for alz_spoke.
  EOT
  type = object({
    vnet_id = string
    subnet_ids = object({
      pe        = string
      apim      = optional(string)
      logic_app = optional(string)
      agent     = optional(string)
    })
    private_dns_zone_ids              = optional(map(string), {})
    dns_zone_groups_managed_by_policy = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.network != null || var.network_mode == "greenfield"
    error_message = "network_mode alz_spoke / byo: set `network` in platform.tfvars (alz_spoke: task output STACK=network NAME=platform_network)."
  }
  validation {
    condition     = var.network == null || try(var.network.subnet_ids.logic_app, null) != null || var.usage_pipeline.logic_app.hosting != "workflow_standard"
    error_message = "usage_pipeline.logic_app.hosting = workflow_standard needs network.subnet_ids.logic_app (regional VNet integration)."
  }
  validation {
    condition     = var.network == null || try(var.network.subnet_ids.apim, null) != null || coalesce(var.apim.vnet_mode, contains(["StandardV2", "PremiumV2"], var.apim.sku) ? "integration" : "external") == "none"
    error_message = "apim.vnet_mode other than none needs network.subnet_ids.apim."
  }
}

variable "features" {
  description = "Optional platform capabilities: api_center deploys Azure API Center; semantic_cache deploys Azure Managed Redis as the APIM external cache."
  type = object({
    api_center     = optional(bool, true)
    semantic_cache = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "foundry" {
  description = <<-EOT
    Microsoft Foundry (AI Services) accounts, projects and model deployments.
      enabled                    false = no Foundry accounts, projects, models or Foundry Application
                                 Insights (e.g. a customer that only wants the Language and Content
                                 Safety services below, or brings its own models through
                                 llm-backend-onboarding llm_backends).
      instances                  One account (+ default project) per entry; name "" = generated.
      models                     Deployments; ai_service_index selects the instance.
      external_access            Public network access to the accounts.
      network_injection_enabled  Inject the Agent Service into the agent subnet.
      outbound_allowed_fqdns     Restrict the accounts' outbound access to these FQDNs (null = unrestricted).
  EOT
  type = object({
    enabled = optional(bool, true)
    instances = optional(list(object({
      name                      = optional(string, "")
      location                  = string
      custom_subdomain          = optional(string, "")
      default_project_name      = optional(string, "citadel-governance-project")
      network_injection_enabled = optional(bool, true)
    })), [{ location = "swedencentral" }])
    models = optional(list(object({
      name             = string
      publisher        = optional(string, "OpenAI")
      version          = string
      sku              = optional(string, "GlobalStandard")
      capacity         = optional(number, 100)
      ai_service_index = optional(number, 0)
    })), [])
    external_access           = optional(bool, false)
    network_injection_enabled = optional(bool, true)
    outbound_allowed_fqdns    = optional(list(string))
  })
  default  = {}
  nullable = false
}

variable "language_service" {
  description = <<-EOT
    A standalone Language service account (kind TextAnalytics) for PII redaction and
    anonymization, for customers that don't deploy Foundry or want the service separate
    from it. It is a Microsoft.CognitiveServices account like the Foundry ones, with a
    private endpoint, Entra-only auth and Cognitive Services User for the APIM identity.
    stacks/gateway-config then uses it with pii_service = { source = "dedicated" }.
      enabled                Deploy the account.
      location               null = the stack location (the service must be available there).
      sku                    S (standard).
      public_network_access  false = private endpoint only.
  EOT
  type = object({
    enabled               = optional(bool, false)
    location              = optional(string)
    sku                   = optional(string, "S")
    public_network_access = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "content_safety_service" {
  description = <<-EOT
    A standalone Azure AI Content Safety account (kind ContentSafety), the counterpart of
    language_service for content safety; stacks/gateway-config uses it with
    content_safety_service = { source = "dedicated" }.
      enabled                Deploy the account.
      location               null = the stack location (the service must be available there).
      sku                    S0.
      public_network_access  false = private endpoint only.
  EOT
  type = object({
    enabled               = optional(bool, false)
    location              = optional(string)
    sku                   = optional(string, "S0")
    public_network_access = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "key_vault" {
  description = "Key Vault settings (RBAC authorization always on)."
  type = object({
    sku                           = optional(string, "standard")
    soft_delete_retention_days    = optional(number, 7)
    purge_protection_enabled      = optional(bool, true)
    public_network_access_enabled = optional(bool, false)
    network_acl_default_action    = optional(string, "Deny")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.key_vault.soft_delete_retention_days >= 7 && var.key_vault.soft_delete_retention_days <= 90
    error_message = "key_vault.soft_delete_retention_days must be between 7 and 90."
  }
  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault.network_acl_default_action)
    error_message = "key_vault.network_acl_default_action must be Allow or Deny."
  }
}

variable "redis" {
  description = "Azure Managed Redis for the semantic cache (features.semantic_cache)."
  type = object({
    sku_name              = optional(string, "Balanced_B10")
    capacity              = optional(number, 2)
    public_network_access = optional(string, "Disabled")
    minimum_tls_version   = optional(string, "1.2")
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^((Balanced_B|MemoryOptimized_M|ComputeOptimized_X|FlashOptimized_A)[0-9]+|Enterprise_E[0-9]+|EnterpriseFlash_F[0-9]+)$", var.redis.sku_name))
    error_message = "redis.sku_name must be an Azure Managed Redis SKU (Balanced_B*, MemoryOptimized_M*, ComputeOptimized_X*, FlashOptimized_A*) or Enterprise_E* / EnterpriseFlash_F*."
  }
}

variable "api_center" {
  description = <<-EOT
    Azure API Center (features.api_center).
      sku                 Free | Standard.
      location            null = the stack location (API Center isn't in every region).
      remote_mcp_servers  Remote (third-party) MCP servers to catalogue next to the gateway's own APIs: an
                          API of kind MCP, a version, a definition and a deployment each. They aren't served by
                          the gateway.
                            name               API Center API name (letters, digits and hyphens), unique
                            description        summary shown in the catalogue
                            url                the server's MCP (SSE) endpoint (runtime URI and VS Code install link)
                            documentation_url  optional documentation link
  EOT
  type = object({
    sku      = optional(string, "Free")
    location = optional(string)
    remote_mcp_servers = optional(list(object({
      name              = string
      description       = string
      url               = string
      documentation_url = optional(string, "")
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Free", "Standard"], var.api_center.sku)
    error_message = "api_center.sku must be Free or Standard."
  }
  validation {
    condition     = alltrue([for m in var.api_center.remote_mcp_servers : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,89}$", m.name))])
    error_message = "api_center.remote_mcp_servers[*].name must be an API Center API name: letters, digits and hyphens, starting with a letter or digit."
  }
  validation {
    condition     = length(var.api_center.remote_mcp_servers) == length(distinct([for m in var.api_center.remote_mcp_servers : m.name]))
    error_message = "api_center.remote_mcp_servers[*].name must be unique."
  }
  validation {
    condition     = alltrue([for m in var.api_center.remote_mcp_servers : can(regex("^https?://[^\\s\"<>]+$", m.url)) && (m.documentation_url == "" || can(regex("^https?://[^\\s\"<>]+$", m.documentation_url)))])
    error_message = "api_center.remote_mcp_servers[*].url and documentation_url must be http(s) URLs without spaces, quotes or angle brackets."
  }
}

variable "apim_logging" {
  description = "Service-level APIM diagnostics (Application Insights): verbosity (verbose | information | error) and body bytes logged."
  type = object({
    verbosity  = optional(string, "information")
    body_bytes = optional(number, 8192)
  })
  default  = {}
  nullable = false
}

variable "usage_pipeline" {
  description = <<-EOT
    Usage ingestion pipeline (Event Hub -> Logic App -> Cosmos DB).
      logic_app.hosting  workflow_standard = WS plan with regional VNet integration (needs shared-key storage);
                         ase_v3 = Isolated v2 plan in an App Service Environment v3 (keyless storage).
      logic_app.sku      null = WS1 (workflow_standard) or I1v2 (ase_v3).
      logic_app.worker_count / max_worker_count
                         ase_v3: autoscale range of the Isolated v2 plan (CPU based).
                         workflow_standard: worker_count = always-ready WS instances (elastic
                         scale-out up to 20 on top); max_worker_count unused.
      logic_app.zone_redundant
                         workflow_standard: zone-redundant WS plan (needs worker_count >= 2 and
                         WS AZ quota in the region) and, for a new storage account, ZRS storage.
                         Set at creation: Azure can't change a plan's zone redundancy later
                         (the plan stops with the two commands that recreate it). ase_v3: use
                         ase.zone_redundant instead.
      logic_app.deployment
                         ase_v3: run_from_package (default; zip in the keyless storage account,
                         read by the usage UAMI) or zip_deploy (az push to SCM from a runner in
                         the VNet). workflow_standard always uses zip_deploy.
      logic_app.private_endpoint / public_network_access / private_endpoint_name
                         workflow_standard only (an ILB ASE is already private). private_endpoint
                         creates one `sites` endpoint for the website and SCM; needs the
                         privatelink.azurewebsites.net zone (greenfield: network.tfvars
                         private_dns.logic_app_zone = true; alz_spoke / byo: network
                         private_dns_zone_ids.logic_app, or Azure Policy). public_network_access
                         = false closes the public website and SCM: workflow publishing then
                         needs a runner on a connected network. The two are independent.
                         private_endpoint_name null = pe-<logic app name>.
      ase.app_service_environment_id
                         ase_v3: a shared / BYO ASE; null = the ASE of stacks/app-hosting,
                         found by name.
      ase.zone_redundant ase_v3: the ASE is zone redundant (app-hosting ase.zone_redundant): the
                         plan is zone balanced (worker_count >= 2) and a new storage account ZRS.
  EOT
  type = object({
    eventhub = optional(object({
      capacity              = optional(number, 1)
      public_network_access = optional(string, "Enabled")
      disaster_recovery = optional(object({
        partner_namespace_id = string
        alias                = optional(string, "default")
      }))
    }), {})
    cosmos = optional(object({
      public_network_access = optional(string, "Disabled")
      local_auth_enabled    = optional(bool, false)
    }), {})
    logic_app = optional(object({
      hosting            = optional(string, "workflow_standard")
      sku                = optional(string)
      worker_count       = optional(number, 1)
      max_worker_count   = optional(number, 3)
      deployment         = optional(string, "run_from_package")
      content_share_name = optional(string, "")
      code_deploy        = optional(bool, false)
      code_source_path   = optional(string, "")
      zone_redundant     = optional(bool, false)

      private_endpoint      = optional(bool, false)
      public_network_access = optional(bool, true)
      private_endpoint_name = optional(string)
    }), {})
    ase = optional(object({
      app_service_environment_id = optional(string)
      zone_redundant             = optional(bool, false)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["workflow_standard", "ase_v3"], var.usage_pipeline.logic_app.hosting)
    error_message = "usage_pipeline.logic_app.hosting must be workflow_standard or ase_v3."
  }
  validation {
    condition = var.usage_pipeline.logic_app.sku == null || (
      var.usage_pipeline.logic_app.hosting == "ase_v3"
      ? can(regex("^I[1-6]v2$", coalesce(var.usage_pipeline.logic_app.sku, "-")))
      : can(regex("^WS[1-3]$", coalesce(var.usage_pipeline.logic_app.sku, "-")))
    )
    error_message = "usage_pipeline.logic_app.sku: ase_v3 needs an Isolated v2 SKU (I1v2..I6v2; the memory-optimised I1mv2..I5mv2 aren't supported by the App Service plan module); workflow_standard needs WS1, WS2 or WS3."
  }
  validation {
    condition     = contains(["run_from_package", "zip_deploy"], var.usage_pipeline.logic_app.deployment)
    error_message = "usage_pipeline.logic_app.deployment must be run_from_package or zip_deploy."
  }
  validation {
    condition     = !var.usage_pipeline.logic_app.private_endpoint || var.usage_pipeline.logic_app.hosting == "workflow_standard"
    error_message = "usage_pipeline.logic_app.private_endpoint applies to hosting = workflow_standard only: a Logic App in an ILB App Service Environment v3 is already private and can't take a private endpoint."
  }
  validation {
    condition     = var.usage_pipeline.logic_app.private_endpoint_name == null || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,78}[A-Za-z0-9_]$", coalesce(var.usage_pipeline.logic_app.private_endpoint_name, "-")))
    error_message = "usage_pipeline.logic_app.private_endpoint_name must be a valid private endpoint name (2-80 characters: letters, digits, '.', '_' or '-')."
  }
  validation {
    condition     = var.usage_pipeline.logic_app.max_worker_count >= var.usage_pipeline.logic_app.worker_count
    error_message = "usage_pipeline.logic_app.max_worker_count must be >= worker_count."
  }
  validation {
    condition     = !var.usage_pipeline.logic_app.zone_redundant || var.usage_pipeline.logic_app.hosting == "workflow_standard"
    error_message = "usage_pipeline.logic_app.zone_redundant applies to hosting = workflow_standard; for ase_v3 set usage_pipeline.ase.zone_redundant = true (matching app-hosting ase.zone_redundant)."
  }
  validation {
    condition = var.usage_pipeline.logic_app.worker_count >= 2 || !(
      var.usage_pipeline.logic_app.hosting == "ase_v3" ? var.usage_pipeline.ase.zone_redundant : var.usage_pipeline.logic_app.zone_redundant
    )
    error_message = "A zone-redundant Logic App plan needs usage_pipeline.logic_app.worker_count >= 2 to span availability zones."
  }
  validation {
    condition     = alltrue([for v in [var.usage_pipeline.eventhub.public_network_access, var.usage_pipeline.cosmos.public_network_access] : contains(["Enabled", "Disabled"], v)])
    error_message = "usage_pipeline.*.public_network_access must be Enabled or Disabled."
  }
}

variable "monitoring" {
  description = <<-EOT
    Log Analytics and Azure Monitor.
      log_analytics_workspace_id       null = create a workspace; set = use this (BYO / platform) workspace.
      log_analytics_subscription_id    Subscription of the BYO workspace when it differs from subscription_id.
      private_link_scope               Create an Azure Monitor Private Link Scope (AMPLS) with a private endpoint
                                       (greenfield / byo: needs network.tfvars private_dns.link_monitor_zone,
                                       or the five Azure Monitor zone IDs in network.private_dns_zone_ids).
                                       Only one scope per network that shares DNS: in an ALZ hub-and-spoke,
                                       join the hub's instead.
      existing_private_link_scope_id   Join an existing scope (e.g. the hub's): the workspace (when created
                                       here) and the App Insights components become its scoped resources.
                                       The apply identity needs write access on that scope.
      private_link_scope_access_mode   { ingestion, query } of the scope created here: Open (default) or
                                       PrivateOnly (the networks reach only resources in the scope).
      public_ingestion_enabled         false: the workspace (when created here) and the components accept
                                       telemetry only through the private link (needs a scope and APIM in a
                                       VNet). Diagnostic settings aren't affected.
      public_query_enabled             false: the Logic App and Foundry App Insights components accept
                                       queries only from networks connected to the scope (portal Logs,
                                       workbooks and dashboards too). The workspace and the APIM component
                                       keep public query: the usage pipeline reads the APIM component with
                                       the Logic App managed connector, whose queries go through Resource
                                       Manager (no private link), and a workspace that blocks public query
                                       returns them empty. The other components' data, stored in the same
                                       workspace, stays queryable there (RBAC applies).
      app_insights_dashboards          Create the Application Insights dashboards.
      app_insights_entra_ingestion     true (default): the APIM and Logic App App Insights components accept
                                       only Microsoft Entra ingestion (local authentication disabled). The
                                       APIM logger and the Logic App runtime send as their managed
                                       identities, which get Monitoring Metrics Publisher on their component,
                                       so the connection string APIM keeps in its generated
                                       Logger-Credentials named value can't be used to send telemetry.
                                       Telemetry can pause for a few minutes on the apply that turns it on
                                       (role propagation). false: instrumentation-key ingestion. The Foundry
                                       component keeps local authentication (Foundry tracing uses its
                                       connection string).
      policy_managed_diagnostics       Services whose Azure Monitor settings belong to Policy:
                                       apim, cosmosdb, eventhub, foundry, logic_app. No workload
                                       settings are created/overwritten for these services. foundry
                                       covers every Cognitive Services account (Foundry, Language,
                                       Content Safety).
    A BYO workspace keeps its own network settings and scope membership (its owner's).
  EOT
  type = object({
    log_analytics_workspace_id     = optional(string)
    log_analytics_subscription_id  = optional(string)
    private_link_scope             = optional(bool, false)
    existing_private_link_scope_id = optional(string)
    private_link_scope_access_mode = optional(object({
      ingestion = optional(string, "Open")
      query     = optional(string, "Open")
    }), {})
    public_ingestion_enabled     = optional(bool, true)
    public_query_enabled         = optional(bool, true)
    app_insights_dashboards      = optional(bool, true)
    app_insights_entra_ingestion = optional(bool, true)
    policy_managed_diagnostics   = optional(set(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(setsubtract(var.monitoring.policy_managed_diagnostics, ["apim", "cosmosdb", "eventhub", "foundry", "logic_app"])) == 0
    error_message = "monitoring.policy_managed_diagnostics accepts apim, cosmosdb, eventhub, foundry and logic_app."
  }

  validation {
    condition = var.monitoring.log_analytics_workspace_id == null || can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$",
      var.monitoring.log_analytics_workspace_id
    ))
    error_message = "monitoring.log_analytics_workspace_id must be a Log Analytics workspace resource ID (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>)."
  }

  validation {
    condition     = !(var.monitoring.private_link_scope && var.monitoring.existing_private_link_scope_id != null)
    error_message = "monitoring: set private_link_scope (create a scope) or existing_private_link_scope_id (join one), not both."
  }

  validation {
    condition     = var.monitoring.existing_private_link_scope_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/microsoft\\.insights/privateLinkScopes/[^/]+$", var.monitoring.existing_private_link_scope_id))
    error_message = "monitoring.existing_private_link_scope_id must be an Azure Monitor Private Link Scope resource ID (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Insights/privateLinkScopes/<name>)."
  }

  validation {
    condition     = alltrue([for m in [var.monitoring.private_link_scope_access_mode.ingestion, var.monitoring.private_link_scope_access_mode.query] : contains(["Open", "PrivateOnly"], m)])
    error_message = "monitoring.private_link_scope_access_mode.ingestion and .query must be Open or PrivateOnly."
  }

  validation {
    condition     = (var.monitoring.public_ingestion_enabled && var.monitoring.public_query_enabled) || var.monitoring.private_link_scope || var.monitoring.existing_private_link_scope_id != null
    error_message = "monitoring.public_ingestion_enabled / public_query_enabled = false need a private link scope: private_link_scope = true or existing_private_link_scope_id."
  }

  validation {
    # APIM sends its App Insights telemetry from its outbound path: without a VNet that's public.
    condition     = var.monitoring.public_ingestion_enabled || var.apim.vnet_mode != "none"
    error_message = "monitoring.public_ingestion_enabled = false needs APIM in a VNet (apim.vnet_mode != \"none\"): its App Insights telemetry would have no private path."
  }
}

variable "dev_access" {
  description = <<-EOT
    Laptop runs without a private runner (greenfield, non-prod only): public CIDRs allowed through the
    Key Vault and usage-storage firewalls (default action stays Deny). Behind proxied egress the services
    see the proxy's address, which can differ per process: use a runner in snet-cicd instead.
  EOT
  type = object({
    allowed_cidrs = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in var.dev_access.allowed_cidrs : can(cidrhost(strcontains(r, "/") ? r : "${r}/32", 0))])
    error_message = "dev_access.allowed_cidrs must be IPv4 addresses or CIDR ranges."
  }
}

variable "secret_writer_principal_ids" {
  description = "Principals that write Key Vault secrets (Secrets Officer): the apply pipeline identity, for access contracts."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "secret_reader_principal_ids" {
  description = "Principals that read Key Vault secrets (Secrets User): the plan pipeline identity."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "deny_storage_shared_key" {
  description = "Assign the built-in policy \"Storage accounts should prevent shared key access\" (Deny) on the workload resource group. Needs usage_pipeline.logic_app.hosting = \"ase_v3\". Skip it when the platform already assigns the ALZ Deny-Storage-Shared-Key policy."
  type        = bool
  default     = false
  nullable    = false
}

variable "purge_soft_delete_on_destroy" {
  description = "Purge soft-deleted Key Vaults, APIM services and Foundry accounts on destroy (needs subscription-level purge rights)."
  type        = bool
  default     = false
}
