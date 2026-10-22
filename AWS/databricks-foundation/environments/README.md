# Environment deployment roots

Development has four wired S3-backed Terraform roots. Apply whole roots in order:
01-infra → 02-account → 03-data-access → 04-workspace. Metastore and data setup
precede compute configuration. Destroy in reverse order and preserve the state bucket.

Staging and production mirror these four folders as scaffolds only; their module
wiring and environment values are not implemented. They are not ready to apply.

Copy backend.hcl.example and terraform.tfvars.example where provided, configure
local values, then run from each development root:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Backend configuration is supplied at initialization, not through tfvars. Keep
backend keys and downstream remote-state keys aligned. After the retired-dev
reorder, initialize the renamed roots with -reconfigure, not -migrate-state.
Other deployments with nonempty old states require a reviewed state migration.
See the [development guide](dev/README.md).
