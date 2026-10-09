# Multi-provider LLM backends

One gateway in front of several model providers:

- two Microsoft Foundry accounts in different regions (`platform.tfvars`),
  with `gpt-5.4-mini` on both so APIM builds a load-balanced backend pool;
- extra backends that aren't Foundry (`llm-backend-onboarding.tfvars`): Azure
  OpenAI outside Foundry (managed identity), a third-party OpenAI-compatible
  endpoint (bearer key) and AWS Bedrock (SigV4);
- model aliases with a `priority` (failover) and a `weighted` strategy.

The third-party and AWS credentials are **Key Vault secret references**
(versionless URIs); no secret value is in Terraform. Create the secrets in
the platform Key Vault (or any vault the APIM identity can read: it needs
`Key Vault Secrets User`) before the first `task apply STACK=llm-backend-onboarding`.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
