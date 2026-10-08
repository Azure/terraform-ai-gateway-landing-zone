# Microsoft Graph only. The apply identity needs Application.ReadWrite.OwnedBy
# (granted by stacks/bootstrap when graph_permissions = true).
provider "azuread" {}
