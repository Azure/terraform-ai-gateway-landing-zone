# Greenfield /22 with the default carve; Workflow Standard needs the Logic App subnet.
address_space   = "10.170.0.0/22"
apim_vnet_mode  = "integration" # = apim.vnet_mode in platform.tfvars
subnets_enabled = { logic_app = true, ase = false, cicd = false }
# Private Logic App (platform.tfvars usage_pipeline.logic_app.private_endpoint = true) also needs:
# private_dns = { logic_app_zone = true }
