apim = {
  sku             = "StandardV2"
  vnet_mode       = "integration"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

foundry = {
  instances = [{ location = "swedencentral" }]
  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = {
    hosting = "ase_v3" # the Logic App runs in the ASE of stacks/app-hosting (found by name)

    # Isolated v2 size: I1v2 to I6v2 (the memory-optimised I1mv2 to I5mv2 aren't supported yet).
    sku = "I2v2"

    # The plan autoscales on CPU between these two: +1 instance above 70 %, -1 below 30 %.
    worker_count     = 2
    max_worker_count = 6

    # How the workflow code reaches the app:
    #   run_from_package  the zip goes to the keyless storage account as a blob and the app loads it
    #                     through its managed identity. Needs a runner that reaches the storage
    #                     private endpoint (the default; verified on an ASE).
    #   zip_deploy        pushed with `az` to <app>.scm.<ase>.appserviceenvironment.net: needs a runner
    #                     inside the VNet that resolves the ASE's private DNS zone.
    deployment  = "run_from_package"
    code_deploy = true # false = create the app without publishing the workflows
  }

  # A shared ASE owned by someone else instead: leave app-hosting.tfvars out and set
  #   ase = { app_service_environment_id = "<resource id>" }   (see examples/shared-ase).
  ase = {
    zone_redundant = true # = ase.zone_redundant in app-hosting.tfvars: the plan is zone-balanced
  }
}

# Assigns the built-in policy "Storage accounts should prevent shared key access" (Deny) on the
# workload resource group, so the pipeline stays keyless (needs hosting = "ase_v3"). Leave it out
# where the platform already assigns the ALZ Deny-Storage-Shared-Key policy.
deny_storage_shared_key = true

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
