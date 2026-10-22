mock_provider "databricks" {
  alias = "accounts"
  mock_resource "databricks_group" { defaults = { id = "500" } }
}
mock_provider "databricks" { alias = "workspace" }

run "rendered_yaml_reaches_terraform_modules" {
  command = apply
  assert {
    condition     = length(output.group_ids) == 4 && length(output.grant_ids) == 9
    error_message = "The demo YAML must reference four bootstrap account groups and yield nine unioned principal/object grants."
  }
  assert {
    condition     = contains(keys(output.grant_ids), jsonencode(["table", "dev_demo.gold.sales_summary", "dev-demo-engineers"]))
    error_message = "The existing-table permission must survive YAML rendering and module wiring."
  }
}
