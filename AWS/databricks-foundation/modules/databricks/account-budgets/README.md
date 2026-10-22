# Databricks account budgets

Creates one monthly Databricks budget with email alerts using the account-level
`databricks.accounts` provider. Requires account administrator credentials.
The provider documents budgets as Public Preview.

The default monthly budget is **10 USD**, with alerts at **5, 8, and 10 USD**
(50%, 80%, 100%). Override `monthly_limit_usd` or
`alert_threshold_percentages` as needed. Supply at least one email recipient.

```hcl
module "account_budget" {
  source = "./modules/databricks/account-budgets"
  providers = { databricks.accounts = databricks.accounts }
  name = "databricks-dev-monthly"
  workspace_ids = [module.workspace.workspace_id]
  alert_email_addresses = ["platform@example.com"]
  monthly_limit_usd = 10
}
```

Omitting `workspace_ids` tracks the entire account. Workspace IDs scope the
budget, not the provider. Alert thresholds must be positive; Databricks allows
at most four unique thresholds per budget. The module does not grant budget
permissions or configure serverless usage policies.

Budgets use Databricks USD list prices, excluding credits and negotiated
discounts. Notifications can be delayed by up to 24 hours. These alerts do not
stop compute or cap spending and do not cover the separate AWS infrastructure
bill (EC2, EBS, S3, NAT gateways, endpoints, and transfer).

Development phase `02-account` creates the workspace budget when
`budget_alert_email_addresses` is non-empty. An empty recipient set leaves
budget creation disabled so no placeholder email receives billing information.
`monthly_budget_usd` defaults to 10 and can be overridden in tfvars.

Outputs: `budget_id` and `alert_thresholds_usd`.

## Validation

```bash
terraform init -backend=false
terraform test
terraform fmt -check -recursive .
```

## References

- [Create and monitor budgets](https://docs.databricks.com/aws/en/admin/account-settings/budgets)
- [Terraform budget resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/budget)
