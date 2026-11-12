# Partial backend: the rest comes from environments/<env>/backend.hcl.
# One state per use case: task contract sets -backend-config="key=<use-case>.tfstate".
terraform {
  backend "azurerm" {
    container_name   = "access-contracts"
    key              = "terraform.tfstate"
    use_azuread_auth = true
  }
}
