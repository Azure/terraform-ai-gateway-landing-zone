# The ASE needs a subnet of its own: a dedicated /24 (a /27 is the minimum), empty and
# delegated to Microsoft.Web/hostingEnvironments. The network stack creates it, with its NSG.
address_space = "10.170.0.0/22"

# Explicit prefix instead of the default carve of address_space (this is the default for a /22).
# Set another one when the range collides with a peered network.
subnet_prefixes = { ase = "10.170.1.0/24" }

apim_vnet_mode = "integration" # = apim.vnet_mode in platform.tfvars

# ase = true creates snet-ase. Workflow Standard's Logic App subnet isn't needed: the ASE hosts the app.
# cicd = true creates snet-cicd for the runner that applies (see the README).
subnets_enabled        = { logic_app = false, agent = false, ase = true, cicd = true }
cicd_subnet_delegation = "github" # GitHub-hosted runners with Azure private networking; "none" = a self-hosted runner VM
