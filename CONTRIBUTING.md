# Contributing

## Local quality checks

The same checks run in CI (`.github/workflows/ci.yml`) on every pull request.

| Check | Command | Config |
|---|---|---|
| Formatting | `terraform fmt -check -recursive` | — |
| Lint (incl. unused / undocumented variables) | `tflint --init && for d in $(scripts/ci/tf-dirs.sh); do tflint --chdir=$d --config=$PWD/.tflint.hcl; done` | `.tflint.hcl` |
| Validate | `terraform -chdir=<dir> init -backend=false && terraform -chdir=<dir> validate` | — |
| Unit tests (mocked, no Azure access) | Roots (`.`, `citadel-access-contracts`, `llm-backend-onboarding`): `terraform -chdir=<dir> init -backend=false -test-directory=tests/unit && terraform -chdir=<dir> test -test-directory=tests/unit`. Modules with tests (e.g. `modules/naming`): `terraform -chdir=<dir> init -backend=false && terraform -chdir=<dir> test` | Roots: `tests/unit/*.tftest.hcl`; modules: `tests/*.tftest.hcl` |
| Module READMEs | `terraform-docs -c .terraform-docs.yml modules/<name>` | `.terraform-docs.yml` |
| Security scan (new findings only) | `checkov --config-file .checkov.yaml` | `.checkov.yaml`, `.checkov.baseline` |
| Secrets | `gitleaks git --config .gitleaks.toml --redact .` | `.gitleaks.toml` |
| Policy XML assets | `scripts/ci/check-policy-assets.sh` | — |

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

- **Lock files are committed** for root configurations (`.terraform.lock.hcl`), and
  CI runs `terraform init -lockfile=readonly`. Update providers with
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64`.
- **Every variable and output has a description**, and every variable has a type.
- **No unused variables.** If an input must stay for compatibility, add it to the
  `DEPRECATED INPUTS` section of `variables.tf` (default `null`) and to the
  `deprecated_inputs` check in `checks.tf`.
- **New root inputs go into the typed objects** in `interfaces.tf` (`apim`,
  `network`, `features`, `usage_pipeline`, `monitoring`) with their defaults in
  `optional()`. The old flat inputs are shims: they default to `null`, override
  the typed attribute when set, and are listed in `local.deprecated_flat_inputs`
  (which drives the `deprecated_flat_inputs` warning).
- **No module-level `depends_on`.** Express ordering through data flow; when a
  consumer must wait for something it doesn't reference (RBAC propagation, an NSG
  association), add `depends_on` to the producing module's output instead.
- **No create-or-lookup inside modules.** Modules receive IDs; the root decides
  whether a resource is created or looked up (`network.tf`, BYO Log Analytics).
- **Moving or renaming a resource needs a `moved {}` block** (`moved.tf`), so an
  upgrade never destroys and recreates it.
- **One copy of each policy XML.** Every XML file must be referenced from Terraform.
- **No secrets in outputs.** Subscription keys are read on demand (Key Vault or
  `listSecrets`), never returned as Terraform outputs.
- **Key Vault secrets** set `content_type` and an `expiration_date` of at most 90
  days (Azure Landing Zone `Enforce-GR-KeyVault`).
- **New checkov findings fail CI.** Fix them, or, if accepted, add a skip with a
  justification. Regenerate `.checkov.baseline` only when a baselined finding is fixed.
