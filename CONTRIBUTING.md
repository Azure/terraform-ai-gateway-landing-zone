# Contributing

## Local quality checks

The same checks run in CI (`.github/workflows/ci.yml`) on every pull request.

| Check | Command | Config |
|---|---|---|
| Formatting | `terraform fmt -check -recursive` | — |
| Lint (incl. unused / undocumented variables) | `tflint --init && for d in $(scripts/ci/tf-dirs.sh); do tflint --chdir=$d --config=$PWD/.tflint.hcl; done` | `.tflint.hcl` |
| Validate | `terraform -chdir=<dir> init -backend=false && terraform -chdir=<dir> validate` | — |
| Unit tests (mocked, no Azure access) | `task test`, or `terraform -chdir=<dir> init -backend=false && terraform -chdir=<dir> test -filter=tests/unit.tftest.hcl` for one module or stack | `tests/unit.tftest.hcl` |
| Examples plan against their stacks | `scripts/ci/check-examples.sh [scenario]` (after `init` in every stack) | `stacks/*/tests/examples.tftest.hcl` |
| Module and stack READMEs | `terraform-docs -c .terraform-docs.yml <modules/name or stacks/name>` | `.terraform-docs.yml` |
| Security scan (new findings only) | `checkov --config-file .checkov.yaml` | `.checkov.yaml`, `.checkov.baseline` |
| Secrets | `gitleaks git --config .gitleaks.toml --redact .` | `.gitleaks.toml` |
| Repository rules | `task lint` runs fmt, tflint and `scripts/ci/check-{common-vars,module-depth,avm-versions,no-remote-state,policy-assets}.sh` | — |

Or run everything at once with [pre-commit](https://pre-commit.com):

```bash
pip install pre-commit
pre-commit install            # run on every commit
pre-commit run --all-files    # run now
```

Tool versions: Terraform from `.terraform-version` (use `tenv` or `tfenv`),
TFLint 0.64, terraform-docs 0.24, checkov 3, gitleaks 8.30. The CI scripts need
bash 4 or later (macOS: `brew install bash`).

## Rules that CI enforces

- **Lock files are committed** for every stack (`stacks/*/.terraform.lock.hcl`), and
  CI runs `terraform init -lockfile=readonly`. Refresh them with `task lock`.
- **Environment files are ignored.** Only `environments/.gitkeep` is tracked;
  commit reusable placeholder templates in `examples/`. Deployment workflows
  restore actual inputs from GitHub environment secrets (see Deployment Guide §7).
- **Three tiers only:** stack → custom module → AVM module. A custom module never
  calls another custom module; one version per AVM module across the repo.
- **Stacks find each other by name** (modules/naming + data sources), never with
  `terraform_remote_state`. `variables.common.tf` and `naming.tf` are identical
  in every stack.
- **Every variable and output has a description**, and every variable has a type.
- **No unused variables.** Remove an input when nothing reads it any more.
- **New inputs go into typed objects** of the owning stack, with their defaults in
  `optional()`, and into the matching `examples/*/<stack>.tfvars` when relevant.
- **No module-level `depends_on`.** Express ordering through data flow; when a
  consumer must wait for something it doesn't reference (RBAC propagation, an NSG
  association), add `depends_on` to the producing module's output instead.
- **No create-or-lookup inside modules.** Modules receive IDs; the stack decides
  whether a resource is created or looked up (`network-lookup.tf`, BYO Log Analytics).
- **One owner per policy asset.** Shared fragments live in
  `stacks/gateway-config/fragments/`, model-aware ones in
  `stacks/llm-backend-onboarding/fragments/`; a fragment file must be wired up
  in its stack's `fragments.tf`.
- **No secrets in outputs or state.** Subscription keys are read with an
  ephemeral action and written to write-only arguments; credentials are Key
  Vault references.
- **Key Vault secrets** set `content_type` and an `expiration_date` of at most 90
  days (Azure Landing Zone `Enforce-GR-KeyVault`).
- **New checkov findings fail CI.** Fix them, or, if accepted, add a skip with a
  justification. Regenerate `.checkov.baseline` only when a baselined finding is fixed.
