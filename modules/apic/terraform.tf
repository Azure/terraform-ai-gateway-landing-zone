terraform {
  required_version = ">= 1.11"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.9, < 3.0"
    }
  }
}
