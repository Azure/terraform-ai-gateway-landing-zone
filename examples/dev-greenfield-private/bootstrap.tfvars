# Used once by `task bootstrap` (Contributor + User Access Administrator). Writes backend.hcl next to this file.
github                 = null     # null = local runs only (no OIDC credentials)
pipeline_identity_mode = "single" # pair (plan + apply) | single (sandbox/dev only)
graph_permissions = false