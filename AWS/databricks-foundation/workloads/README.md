# Workload access declarations

Each workload owns a folder under `AWS/databricks-foundation/workloads/`. Its `dev-demo.yaml` requests
a platform-approved persona and data access for the development demo workspace.

```text
workloads/
  data-engineering/dev-demo.yaml
  data-analytics/dev-demo.yaml
  data-science/dev-demo.yaml
```

For example:

```yaml
version: 1
environment: dev
workspace: demo
persona: engineers
data_access:
  - id: bronze-write
    catalog: dev_demo
    schema: bronze
    access: writer
    reason: Maintain bronze ingestion tables
```

Add `table: sales_summary` for a table-specific request; omit schema/table for
catalog usage only. `access` names a platform-defined permission package, not
raw Databricks privileges. Include stable request IDs and reasons. Empty
`data_access: []` means no data grants requested by this workload.

The platform owns the workload-to-group mapping and permitted catalogs in
[`resources/dev/demo.yaml`](../platform/access/resources/dev/demo.yaml).
The requested persona must match that group's approved persona. A workload
cannot choose another group, define privileges, or request compute policies,
warehouses or capabilities. Compute comes entirely from the platform-owned
[`roles.yaml`](../platform/access/roles.yaml).
People and group membership are managed outside these declarations.

To add another workload, have the platform register its group/catalog limits,
then add `<workload>/dev-demo.yaml` with the matching persona. This initial
implementation accepts dev/demo only; other target files fail validation.
The folder name supplies workload identity; do not add a `team`, `principal`
or `workload` field. IDs must be unique within the workload/target.

From `AWS/databricks-foundation/`:

```bash
python3 -m pip install -r tools/databricks-access/requirements.txt
python3 tools/databricks-access/access.py validate --environment dev --workspace demo
python3 tools/databricks-access/access.py preview --environment dev --workspace demo
```

See the [tool instructions](../tools/databricks-access/README.md)
for an isolated virtual environment and tests. CI runs offline validation/preview
on workload changes. No API apply or permission changes are performed yet.
GitHub reviewer enforcement and live API provisioning remain future work.
