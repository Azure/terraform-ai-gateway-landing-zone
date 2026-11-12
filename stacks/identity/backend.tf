# Partial backend: the rest comes from environments/<env>/backend.hcl.
terraform {
  backend "azurerm" {
    container_name   = "identity"
    key              = "terraform.tfstate"
    use_azuread_auth = true
  }
}
