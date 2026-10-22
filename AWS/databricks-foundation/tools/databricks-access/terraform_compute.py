#!/usr/bin/env python3
"""Compile persona compute YAML and execute reviewed root04 plans for dev/demo."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from configuration import ConfigError, FOUNDATION, load_compute, require
from desired import compile_policy
from identity_check import IdentityCheckError
import terraform_entitlements as features
import terraform_environment as provision
from deprovision_environment import managed, read_state
from environment import ConfigError as EnvironmentConfigError, state_keys
from terraform_permissions import check_saved_plan, digest

ROOT = '04-workspace'


def render(bundle):
    policies = {name: {**compile_policy(policy), 'permissions': {'groups': {}}}
                for name, policy in sorted(bundle['compute']['cluster_policies'].items())}
    warehouses = {name: {'cluster_size': item['size'], 'auto_stop_mins': item['auto_stop_minutes'],
                         'min_num_clusters': item['min_clusters'], 'max_num_clusters': item['max_clusters'],
                         'enable_serverless_compute': item['enable_serverless_compute'],
                         'permissions': {'groups': {}}}
                  for name, item in sorted(bundle['compute']['sql_warehouses'].items())}
    for group in bundle['principals']['groups'].values():
        persona = bundle['roles']['personas'][group['persona']]
        for name in persona['cluster_policies']:
            policies[name]['permissions']['groups'][group['display_name']] = 'CAN_USE'
        for name, level in persona['sql_warehouses'].items():
            warehouses[name]['permissions']['groups'][group['display_name']] = level
    require(all(item['permissions']['groups'] for item in [*policies.values(), *warehouses.values()]),
            'Each declared policy/warehouse must have an explicit persona permission owner')
    return {'cluster_policies': policies, 'warehouses': warehouses, 'read_data_access_state': False}


def bind_values(bundle, intent, account_state):
    bound = features.bind_values(bundle, features.render(bundle), account_state)
    return {**intent, 'compute_identity': features.target_identity(bound),
            'compute_group_ids': {group['display_name']: bound['groups'][key]['group_id']
                                  for key, group in bundle['principals']['groups'].items()}}


def addresses(intent):
    result = {'module.cluster_policies.terraform_data.validation',
              'module.sql_warehouses.terraform_data.validation', 'module.job.terraform_data.validation',
              'terraform_data.compute_binding[0]'}
    for name in intent['cluster_policies']:
        result.update({f'module.cluster_policies.databricks_cluster_policy.this[{json.dumps(name)}]',
                       f'module.cluster_policies.databricks_permissions.cluster_policy[{json.dumps(name)}]'})
    for name in intent['warehouses']:
        result.update({f'module.sql_warehouses.databricks_sql_endpoint.this[{json.dumps(name)}]',
                       f'module.sql_warehouses.databricks_permissions.warehouse[{json.dumps(name)}]'})
    return result


def state_address(resource, instance):
    prefix = '.'.join(filter(None, (resource.get('module'), resource['type'], resource['name'])))
    return prefix + (f'[{json.dumps(instance["index_key"])}]' if 'index_key' in instance else '')


def check_ownership(values, states):
    own = states[ROOT] or {}
    if managed(own):
        outputs = own.get('outputs', {})
        require(outputs.get('target_identity', {}).get('value') == values['compute_identity'] and
                outputs.get('compute_group_ids', {}).get('value') == values['compute_group_ids'],
                'Root04 identity/group binding is missing or changed; review ownership migration')
    for resource in managed(own):
        for instance in resource['instances']:
            require(not instance.get('deposed') and state_address(resource, instance) in addresses(values),
                    'Root04 contains resources outside YAML compute ownership; review migration')
    for root, state in states.items():
        if root == ROOT:
            continue
        for resource in managed(state or {}):
            if resource['type'] == 'databricks_permissions':
                owned_ids = {str(instance['attributes']['id'])
                             for owned in managed(own)
                             if owned['type'] in {'databricks_cluster_policy', 'databricks_sql_endpoint'}
                             for instance in owned['instances']}
                for instance in resource['instances']:
                    attributes = instance['attributes']
                    require(not any(str(attributes.get(field)) in owned_ids
                                    for field in ('cluster_policy_id', 'sql_endpoint_id')),
                            f'Compute permissions are already owned by {root}; review ACL migration')
            if resource['type'] in {'databricks_cluster_policy', 'databricks_sql_endpoint'}:
                for instance in resource['instances']:
                    name = instance['attributes'].get('name')
                    names = values['cluster_policies'] if resource['type'] == 'databricks_cluster_policy' else values['warehouses']
                    require(name not in names, f'Compute object {name} is already owned by {root}')


def check_features(bundle, account_state, states):
    bound = features.bind_values(bundle, features.render(bundle), account_state)
    state = states['02-workspace-access']
    require(state and managed(state), 'Apply root02 and workspace entitlements before compute planning')
    features.check_ownership(bound, states)
    actual = {str(instance['attributes'].get('group_id')): instance['attributes']
              for resource in managed(state) for instance in resource['instances']}
    for group in bound['groups'].values():
        require(all(actual.get(group['group_id'], {}).get(field) == group[field] for field in features.ENTITLEMENTS),
                'Workspace entitlement state differs from persona YAML; apply features before compute')


def preflight(bundle, intent, values, states, retirement=False):
    bound = features.bind_values(bundle, features.render(bundle), states['02-account'])
    features.preflight(bound, features.render(bundle))
    from databricks.sdk import WorkspaceClient
    workspace = WorkspaceClient(host=values['compute_identity']['workspace_url'], auth_type='oauth-m2m',
                                client_id=os.environ['DATABRICKS_CLIENT_ID'],
                                client_secret=os.environ['DATABRICKS_CLIENT_SECRET'])
    if not retirement:
        versions = {item.key for item in workspace.clusters.spark_versions().versions}
        nodes = {item.node_type_id for item in workspace.clusters.list_node_types().node_types}
        for name, policy in bundle['compute']['cluster_policies'].items():
            require(set(policy['runtime']['allowed_versions']) <= versions,
                    f'Policy {name}: approved runtimes are unavailable in this workspace')
            for field in ('worker_nodes', 'driver_nodes'):
                require(set(policy[field]['allowed_types']) <= nodes,
                        f'Policy {name}: approved {field} are unavailable in this workspace')
    for kind, key, objects in (
        ('databricks_cluster_policy', 'cluster_policies', workspace.cluster_policies.list()),
        ('databricks_sql_endpoint', 'warehouses', workspace.warehouses.list()),
    ):
        owned = {instance['attributes']['name']: str(instance['attributes']['id'])
                 for resource in managed(states[ROOT] or {}) if resource['type'] == kind
                 for instance in resource['instances']}
        for item in objects:
            if item.name in intent[key]:
                object_id = str(item.policy_id if kind == 'databricks_cluster_policy' else item.id)
                require(owned.get(item.name) == object_id,
                        f'Existing {key} object {item.name} requires reviewed import; names do not authorize adoption')


def check_plan(plan, intent, retirement=False):
    allowed = (['delete'], ['no-op']) if retirement else (['create'], ['update'], ['no-op'])
    for change in plan.get('resource_changes', []):
        if change['mode'] == 'managed':
            require(change['address'] in addresses(intent), f'Plan contains forbidden resource: {change["address"]}')
            require(change['change']['actions'] in allowed,
                    'Compute deletion/replacement or non-retirement mutation requires separate review')


def source_digest():
    paths = set()
    for folder in ('platform/compute', 'platform/access', 'platform/environments', 'platform/terraform-inputs',
                   'tools/databricks-access', 'tools/environment', 'modules/databricks', f'environments/dev/{ROOT}'):
        paths.update(path for path in (FOUNDATION / folder).rglob('*') if path.is_file()
                     and path.suffix in {'.py', '.tf', '.hcl', '.yaml', '.json', '.txt'}
                     and not any(part in {'.terraform', '__pycache__', 'tests', 'generated-tests'} for part in path.parts)
                     and not path.name.endswith(('.tfvars', '.tfvars.json')))
    return digest({str(path.relative_to(FOUNDATION)): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in sorted(paths)})


def execute(args):
    require(not any(key.startswith(('TF_VAR_', 'TF_CLI_ARGS')) or key in
                    {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'} for key in os.environ),
            'Remove Terraform environment overrides before running')
    bundle = load_compute(environment=args.environment, workspace=args.workspace)
    intent = render(bundle)
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if args.action == 'render':
        (args.artifacts / 'compute.tfvars.json').write_text(json.dumps(intent, indent=2, sort_keys=True) + '\n')
        (args.artifacts / 'compute.intent.json').write_text(json.dumps(intent, indent=2, sort_keys=True) + '\n')
        print('Offline compute inputs only; policy/warehouse deployment requires verified root02 and entitlement state.')
        return
    require(os.environ.get('GITHUB_REF') == 'refs/heads/main' and
            os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch', 'Live compute actions require manual dispatch on main')
    retirement = args.action in {'preview-destroy', 'destroy'}
    applying = args.action in {'apply', 'destroy'}
    if applying:
        provision.require_demo_apply(args.confirm_environment, destroy=retirement)
    require(args.state_bucket and args.state_region, 'State bucket and region are required')
    provision.check_identity(bundle['provisioning'])
    keys = state_keys(bundle['provisioning'])
    keys.update({'02-workspace-access': 'databricks/dev/demo/02-workspace-access.tfstate',
                 '05-permissions': 'databricks/dev/demo/05-permissions.tfstate'})
    backend = {'bucket': args.state_bucket, 'region': args.state_region, 'key': keys[ROOT]}
    plan = args.artifacts.resolve() / 'terraform.tfplan'
    metadata = args.artifacts.resolve() / 'manifest.json'
    with tempfile.TemporaryDirectory(prefix='databricks-compute-') as temporary:
        temporary = Path(temporary)
        states = {root: read_state(args.state_bucket, key, args.state_region, temporary) for root, key in keys.items()}
        empty = retirement and not managed(states[ROOT] or {})
        values = None if empty else bind_values(bundle, intent, states['02-account'])
        if values:
            check_ownership(values, states)
            if not retirement:
                check_features(bundle, states['02-account'], states)
        binding = {'version': 1, 'operation': 'retire-compute' if retirement else 'workspace-compute',
                   'commit': provision.capture(['git', '-C', str(FOUNDATION), 'rev-parse', 'HEAD']),
                   'source_digest': source_digest(), 'inputs': values, 'backend': backend,
                   'states': {root: digest(state) for root, state in states.items()}, 'noop': empty}
        if applying:
            check_saved_plan(json.loads(metadata.read_text()), binding, plan.read_bytes())
        else:
            require(not plan.exists() and not metadata.exists(), 'Artifacts already contain a plan; choose a fresh directory')
        if empty:
            if not applying:
                plan.write_bytes(b'no-owned-workspace-compute\n')
                features.save_manifest(metadata, binding, plan.read_bytes())
            print('Root04 has no managed compute; no retirement required.')
            return
        preflight(bundle, intent, values, states, retirement)
        checkout = temporary / 'foundation'
        for folder in ('modules', f'environments/dev/{ROOT}'):
            shutil.copytree(FOUNDATION / folder, checkout / folder, ignore=provision.ignore)
        root = checkout / 'environments/dev' / ROOT
        variables = temporary / 'compute.tfvars.json'
        # Legacy root04 maps default empty; never load local tfvars or implicit backend values.
        variables.write_text(json.dumps({**values, 'state_bucket': args.state_bucket, 'state_region': args.state_region,
                                         'infra_state_key': keys['01-infra'], 'account_state_key': keys['02-account'],
                                         'data_access_state_key': keys['03-data-access']}, sort_keys=True))
        backend_file = temporary / 'backend.hcl'
        backend_file.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in backend.items()) +
                                '\nuse_lockfile = true\nencrypt = true\n')
        provision.run(['terraform', 'init', '-input=false', '-lockfile=readonly', f'-backend-config={backend_file}'], root)
        provision.run(['terraform', 'validate'], root)
        if not applying:
            command = ['terraform', 'plan', '-input=false', '-lock-timeout=60s', f'-var-file={variables}', f'-out={plan}']
            if retirement:
                command.append('-destroy')
            provision.run(command, root)
        document = json.loads(subprocess.check_output(['terraform', 'show', '-json', str(plan)], cwd=root, text=True))
        check_plan(document, intent, retirement)
        if applying:
            provision.run(['terraform', 'apply', '-input=false', '-lock-timeout=60s', str(plan)], root)
        else:
            features.save_manifest(metadata, binding, plan.read_bytes())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('render', 'plan', 'apply', 'preview-destroy', 'destroy'))
    parser.add_argument('--environment', default='dev')
    parser.add_argument('--workspace', default='demo')
    parser.add_argument('--state-bucket')
    parser.add_argument('--state-region')
    parser.add_argument('--confirm-environment')
    parser.add_argument('--artifacts', required=True, type=Path)
    try:
        execute(parser.parse_args(argv))
    except (ConfigError, EnvironmentConfigError, IdentityCheckError) as exc:
        print(f'Compute execution blocked: {exc}', file=sys.stderr)
        return 1
    except Exception as exc:
        print(f'Compute execution failed ({type(exc).__name__}); SDK details are redacted', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
