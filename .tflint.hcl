# TFLint configuration — used by pre-commit and .github/workflows/ci.yml.
# Run per configuration directory: tflint --chdir=<dir> --config="$PWD/.tflint.hcl"

config {
  # Lint our own local modules where they are called; registry modules are linted upstream.
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

rule "terraform_documented_variables" { enabled = true }
rule "terraform_documented_outputs" { enabled = true }
rule "terraform_typed_variables" { enabled = true }
rule "terraform_unused_declarations" { enabled = true }
rule "terraform_naming_convention" { enabled = true }

# Root configurations pin archive/null/time for the versions their child modules
# use, so a provider can be "required" without a resource in the root itself.
rule "terraform_unused_required_providers" { enabled = false }


# prevent_destroy can't be conditional, so it would block teardown of dev and
# quickstart environments. Production protection uses CanNotDelete resource locks
# (var.lock / AVM `lock` interface) instead — review finding S5.
rule "azurerm_resources_missing_prevent_destroy" { enabled = false }
