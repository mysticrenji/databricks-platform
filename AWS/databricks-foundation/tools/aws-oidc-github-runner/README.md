# GitHub Actions OIDC role for AWS

This Terraform configuration creates an AWS IAM OpenID Connect provider for
GitHub Actions and an IAM role that selected workflows can assume. It does not
create an EC2 self-hosted runner: GitHub-hosted or self-hosted runners use this
role to obtain short-lived AWS credentials without storing AWS access keys in
GitHub.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your repository and a least-privilege policy ARN.
terraform init
terraform plan
terraform apply
```

Use the output role ARN in a workflow:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: eu-west-1
```

The `github_subjects` variable must be restricted to a protected branch or a
GitHub environment. Keep the role's policies least-privilege; no AWS managed
administrator policy is attached by this module.

GitHub repositories created after July 15, 2026 use immutable owner and
repository IDs in the OIDC `sub` claim. For this repository's `main` branch,
use `repo:mysticrenji@10666267/databricks-platform-engineering@1381968032:ref:refs/heads/main`.

The environment/workspace workflows use GitHub Environment subjects instead
of the branch subject. For dev/demo, add these explicit `github_subjects`
entries while preserving the existing branch subject for OIDC verification:

```hcl
"repo:mysticrenji@10666267/databricks-platform-engineering@1381968032:environment:dev-demo-plan"
"repo:mysticrenji@10666267/databricks-platform-engineering@1381968032:environment:dev-demo-apply"
```

Use `dev-sandbox-plan`/`dev-sandbox-apply` for a sandbox workspace. Each new
workspace pair needs matching trust entries; the setup helper creates GitHub
settings but does not apply IAM trust-policy changes.
