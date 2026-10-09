# Used once by `task bootstrap` (Owner). Writes backend.hcl next to this file.
github                         = { repository = "<owner>/<repo>" }
pipeline_identity_mode         = "pair"
create_workload_resource_group = false # the APIM resource group already exists
graph_permissions              = false # no identity stack here
