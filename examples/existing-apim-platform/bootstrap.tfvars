# Used once by `task bootstrap` (Contributor + User Access Administrator). Writes backend.hcl next to this file.
github                         = null                              # null = local runs only (no OIDC credentials)
pipeline_identity_mode         = "single"                          # pair (plan + apply) | single (sandbox/dev only)
create_workload_resource_group = false # the APIM resource group already exists
graph_permissions              = false # no identity stack here
