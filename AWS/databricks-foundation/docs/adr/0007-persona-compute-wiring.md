# ADR 0007: Persona compute YAML compiled into root04 Terraform

- Date: 2026-10-19
- Status: Accepted by the user for feature-branch implementation
- Extends ADR 0006's prior offline-only compute boundary for dev/demo

## Decision

Reuse the existing compute YAML, persona mappings and policy/warehouse modules.
Root04 owns policies, the analytics warehouse and authoritative group ACLs in its
existing `databricks/dev/demo/04-workspace.tfstate`. Engineers and ML users receive
their declared policy CAN_USE; analysts receive SQL warehouse CAN_USE without a
cluster policy. Admins manage the warehouse and already manage policies through
workspace ADMIN. Root02 groups/assignments, external memberships, workspace feature
entitlements and root05 data grants retain their separate owners.

Python validates/renders offline and performs read-only identity, availability,
feature-state and ownership checks. Terraform performs writes. The dev/demo path
uses root04 without root03 state only when UC log/init-script volumes and uploads
are disabled. Legacy callers retain the default root03 dependency. No matching-name
adoption, silent ownership moves or dropping of unrelated root04 resources occurs.

## Execution

Provision after workspace entitlements. Retire compute before entitlements/groups
and infrastructure. Manual main-only dev/demo execution uses the existing verified
administrator policy, separate apply/destroy opt-ins and exact target confirmation.
Saved plans expire after 24 hours and bind source/commit, inputs, backend, all six
states and plan bytes. Reject unexpected resources and normal deletion/replacement.
Retirement applies a separately bound destroy-only plan. Direct teardown guards
remain enforced. Preview-only deprovision previews compute/features and stops.
Storage retention/purge confirmations and backend/KMS preservation are unchanged.

## Consequences

No data-object/metastore registration is required to configure compute. SQL data
access still needs root05 grants. Policy creation starts no clusters, while future
warehouse creation can start billable compute. Default and inherited access can
widen effective permissions and is not silently adopted. PR checks run credential-free
Python and mocked Terraform tests, including rendered inputs through root04. No
live cloud changes or state migration occur during implementation/tests. Other
targets remain outside this feature. See the [compute guide](../../tools/databricks-access/COMPUTE.md).
