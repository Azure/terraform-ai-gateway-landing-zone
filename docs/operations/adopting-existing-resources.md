# Adopting resources that already exist

Terraform only manages what is in its state. If an object already exists in
Azure but not in the state (after a partial run, a lost or reset state, or an
object created by hand or by the Bicep accelerator), `apply` fails with
`A resource with the ID "..." already exists` or `RoleAssignmentExists`.

The fix is declarative: an `import {}` block tells Terraform to adopt the
object during the next plan/apply. The plan shows each import, so it can be
reviewed like any other change. Imperative `terraform import` scripts are no
longer used.

## Main deployment (root)

1. Run the deployment. If apply fails with `already exists`, the deploy script
   prints ready-to-paste blocks:

   ```hcl
   import {
     to = module.apim.azurerm_api_management_named_value.this["foo"]
     id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim>/namedValues/foo"
   }
   ```

   To print them from any saved apply log:

   ```bash
   python3 scripts/import-blocks-from-log.py apply.log
   ```

2. Paste the blocks into `imports.tf` in the repository root.
3. For role assignments, replace `<scope>` with the scope shown in the plan,
   for example `/subscriptions/<sub>/resourceGroups/<rg>`.
4. Run plan. Check that the plan says `will be imported` (and, ideally, no
   further changes to the imported objects), then apply.
5. Delete the blocks. Once the objects are in state, the blocks are no-ops.

## Upgrading an existing environment to Azure Verified Modules (Phase 2)

Some resources moved from azurerm resources to Azure Verified Modules that
manage them with azapi (WP-2.3: the usage-pipeline storage account, its Azure
Files content share and the App Service plan). A `moved {}` block can't cross
resource types, so the owning module drops the v1 resource from state with
`removed { lifecycle { destroy = false } }` and the root (`adopt.tf`) imports the
same Azure resource into the AVM module.

1. For the upgrade run of an environment deployed before Phase 2, set:

   ```hcl
   adopt_existing_resources = true
   ```

2. Run plan. Expect, for each adopted resource, `will be imported` (with an
   in-place update that only touches azapi metadata), and for the old azurerm
   address `will no longer be managed by Terraform, but will not be destroyed`.
   Nothing may be replaced or destroyed.
3. Apply, then set `adopt_existing_resources = false` (or leave it; the imports
   are no-ops once the resources are in state).

New environments leave it `false`. If an existing environment is upgraded
without the flag, apply fails with "already exists" for the adopted resources;
re-run with the flag set and they are imported.

## Sub-deployments (built in)

`llm-backend-onboarding/imports.tf` and `citadel-access-contracts/imports.tf`
contain permanent, conditional import blocks:

| Stack | Adopted when they exist under the APIM service |
|---|---|
| `llm-backend-onboarding` | LLM backends, backend pools, routing and static policy fragments, `resolve-model-alias`, the AWS named values, backend API-key named values |
| `citadel-access-contracts` | The use case's products, product policies, subscriptions (`<code>-<bu>-<use-case>-<env>-SUB-01`) and product–API links |

They list the existing children of the APIM service at plan time
(`azapi_resource_list`), import only what exists, and leave objects that are
already in state alone. A re-run after a state loss, or onboarding a use case
that was created elsewhere, just shows `will be imported` in the plan.

## Azure Monitor logger

APIM can create the `azuremonitor` logger by itself. The gateway upserts it
with an idempotent ARM `PUT` (`azapi_resource_action` in
`modules/apim-telemetry`), so it never needs importing.
