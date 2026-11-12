# Partial backend: the rest comes from environments/<env>/backend.hcl.
# task bootstrap applies with local state first (backend_override.tf), then
# migrates the state into the account it just created.
terraform {
  backend "azurerm" {
    container_name   = "bootstrap"
    key              = "terraform.tfstate"
    use_azuread_auth = true
  }
}
