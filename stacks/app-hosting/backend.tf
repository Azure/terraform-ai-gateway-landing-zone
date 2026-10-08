# Partial backend: the rest comes from environments/<env>/backend.hcl.
terraform {
  backend "azurerm" {
    container_name   = "app-hosting"
    key              = "terraform.tfstate"
    use_azuread_auth = true
  }
}
