#!/usr/bin/env python3
"""Plan workspace feature entitlements independently of datasets and compute."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from configuration import ConfigError, FOUNDATION, load_workspace_access, require
from identity_check import IdentityCheckError, verify_identity
from terraform_permissions import (bind_bootstrap_groups, check_saved_plan, digest,
                                   instances)
import terraform_environment as provision
from deprovision_environment import managed, read_state
from environment import ConfigError as EnvironmentConfigError, state_keys

ROOT = '02-workspace-access'
ENTITLEMENTS = ('workspace_access', 'databricks_sql_access', 'allow_cluster_create',
                'allow_instance_pool_create')


def render(bundle):
    """Offline intent deliberately has no fabricated SCIM IDs or live target."""
    result = {}
    for key, group in bundle['principals']['groups'].items():
        require(group['lifecycle'] == 'terraform', 'Workspace feature groups must be owned by root 02')
        persona = bundle['roles']['personas'][group['persona']]
        entitlements = persona['entitlements']
        require(all(isinstance(entitlements.get(field), bool) for field in ENTITLEMENTS),
                f'Persona {group["persona"]} must explicitly configure all four entitlements')
        result[key] = {'display_name': group['display_name'], 'workspace_role': persona['workspace_role'],
                       'lifecycle': 'terraform', 'entitlements': {field: entitlements[field] for field in ENTITLEMENTS}}
    return {'groups': result}


def bind_values(bundle, intent, account_state):
    outputs = (account_state or {}).get('outputs', {})
    workspace_id = str(outputs.get('workspace_id', {}).get('value', ''))
    workspace_url = outputs.get('workspace_url', {}).get('value', '')
    require(re.fullmatch(r'[1-9][0-9]*', workspace_id), 'Root 02 must export a positive numeric workspace ID')
    require(isinstance(workspace_url, str) and
            re.fullmatch(r'https://[a-z0-9-]+\.cloud\.databricks\.com', workspace_url),
            'Root 02 must export a canonical AWS Databricks workspace URL')
    bound = bind_bootstrap_groups({**intent, 'workspace_id': int(workspace_id)}, account_state)
    return {'environment_name': 'dev', 'workspace_key': 'demo',
            'account_id': bundle['provisioning']['databricks']['account_id'],
            'workspace_id': int(workspace_id), 'workspace_url': workspace_url,
            'groups': {key: {'group_id': group['account_group_id'], 'workspace_role': group['workspace_role'],
                             **group['entitlements']} for key, group in bound['groups'].items()}}


def target_identity(values):
    return {'environment': values['environment_name'], 'workspace': values['workspace_key'],
            **{key: str(values[key]) for key in ('account_id', 'workspace_id', 'workspace_url')}}


def check_ownership(values, states):
    group_ids = {group['group_id'] for group in values['groups'].values()}
    for root, state in states.items():
        if root == ROOT:
            require(all(resource['type'] == 'databricks_entitlements' for resource in managed(state or {})),
                    'Workspace access state contains resources outside entitlement ownership')
            if managed(state or {}):
                outputs = state.get('outputs', {})
                require(outputs.get('target_identity', {}).get('value') == target_identity(values),
                        'Workspace access state is bound to a different or unknown target')
                require(outputs.get('group_ids', {}).get('value') ==
                        {key: group['group_id'] for key, group in values['groups'].items()},
                        'Workspace access group IDs changed; review ownership migration')
            for resource in managed(state or {}):
                for instance in resource['instances']:
                    if instance.get('deposed'):
                        raise ConfigError('Workspace access contains a deposed instance; review retirement')
                    key = instance.get('index_key')
                    require(key in values['groups'] and
                            str(instance['attributes'].get('group_id')) == values['groups'][key]['group_id'],
                            'Workspace access state contains an unexpected group binding')
            continue
        for item in instances(state, 'databricks_entitlements'):
            require(str(item.get('group_id')) not in group_ids,
                    f'Group entitlements are already owned by {root}; review ownership migration')
        # Older inline group entitlement fields may still own the same API settings.
        for item in instances(state, 'databricks_group'):
            if str(item.get('id')) in group_ids:
                require(not any(item.get(field) for field in ENTITLEMENTS),
                        f'Inline group entitlements are already owned by {root}; review ownership migration')
                require(root == '02-account', f'Bootstrap group is already owned by {root}')


def preflight(values, intent):
    """Identity/group checks only; do not read catalogs, grants or metastores."""
    require(os.environ.get('DATABRICKS_ACCOUNT_ID') == values['account_id'],
            'CI account must match environment provisioning configuration')
    require(os.environ.get('DATABRICKS_CLIENT_ID') and os.environ.get('DATABRICKS_CLIENT_SECRET'),
            'OAuth M2M credentials are required')
    from databricks.sdk import AccountClient, WorkspaceClient
    credentials = dict(auth_type='oauth-m2m', client_id=os.environ['DATABRICKS_CLIENT_ID'],
                       client_secret=os.environ['DATABRICKS_CLIENT_SECRET'])
    account = AccountClient(host='https://accounts.cloud.databricks.com', account_id=values['account_id'], **credentials)
    workspace = WorkspaceClient(host=values['workspace_url'], **credentials)
    for line in verify_identity(account, workspace, values['account_id'], str(values['workspace_id']), values['workspace_url']):
        print(line, flush=True)
    assignments = list(account.workspace_assignment.list(workspace_id=values['workspace_id']))
    for key, group in values['groups'].items():
        name = intent['groups'][key]['display_name']
        found = list(account.groups.list(filter=f'displayName eq "{name}"'))
        require(len(found) == 1 and str(found[0].id) == group['group_id'],
                f'Live group identity differs from root 02: {name}')
        matching = [item for item in assignments
                    if item.principal and str(item.principal.principal_id) == group['group_id']]
        require(len(matching) == 1, f'Live workspace assignment missing or ambiguous: {name}')
        permissions = [getattr(permission, 'value', permission) for permission in matching[0].permissions or []]
        require(permissions == [group['workspace_role']], f'Live workspace role differs from root 02: {name}')


def check_plan(plan, retirement=False):
    allowed = (['delete'], ['no-op']) if retirement else (['create'], ['update'], ['no-op'])
    for change in plan.get('resource_changes', []):
        if change['mode'] == 'managed':
            require(change['type'] == 'databricks_entitlements',
                    f'Plan contains forbidden resource type: {change["type"]}')
            require(change['change']['actions'] in allowed,
                    'Plan contains an unreviewed entitlement deletion/replacement or retirement mutation')


def source_digest():
    paths = set()
    for folder in ('platform/access', 'platform/environments', 'platform/terraform-inputs',
                   'tools/databricks-access', 'tools/environment',
                   'modules/databricks/workspace-entitlements', f'environments/dev/{ROOT}'):
        paths.update(path for path in (FOUNDATION / folder).rglob('*') if path.is_file()
                     and path.suffix in {'.py', '.tf', '.hcl', '.yaml', '.json', '.txt'}
                     and not any(part in {'.terraform', '__pycache__', 'tests'} for part in path.parts)
                     and not path.name.endswith(('.tfvars', '.tfvars.json')))
    return digest({str(path.relative_to(FOUNDATION)): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in sorted(paths)})


def save_manifest(path, binding, plan_bytes):
    path.write_text(json.dumps({'binding': binding, 'plan_sha256': hashlib.sha256(plan_bytes).hexdigest(),
                                'expires_at': (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()},
                               indent=2, sort_keys=True) + '\n')


def execute(args):
    require(not any(key.startswith(('TF_VAR_', 'TF_CLI_ARGS')) or key in
                    {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'} for key in os.environ),
            'Remove Terraform environment overrides before running')
    bundle = load_workspace_access(environment=args.environment, workspace=args.workspace)
    intent = render(bundle)
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if args.action == 'render':
        (args.artifacts / 'workspace-access.intent.json').write_text(json.dumps(intent, indent=2, sort_keys=True) + '\n')
        print('Offline entitlement intent only; live Terraform inputs require verified root 02 group IDs.')
        return
    require(os.environ.get('GITHUB_REF') == 'refs/heads/main',
            'Live workspace feature actions are allowed only on main')
    if args.action == 'check-approval':
        provision.require_demo_apply(args.confirm_environment)
        print('dev/demo single-admin deployment checks passed; no AWS/Databricks calls or Terraform execution.')
        return
    require(args.state_bucket and args.state_region, 'State bucket and region are required')
    retirement = args.action in {'preview-destroy', 'destroy'}
    applying = args.action in {'apply', 'destroy'}
    if args.action == 'destroy':
        require(args.confirm_environment == f'{args.environment}/{args.workspace}',
                'Destroy requires matching --confirm-environment dev/demo')
    if args.action == 'apply':
        provision.require_demo_apply(args.confirm_environment)
    elif args.action == 'destroy':
        provision.require_demo_apply(args.confirm_environment, destroy=True)
    config = bundle['provisioning']
    provision.check_identity(config)
    keys = {root: key for root, key in state_keys(config).items() if root in {'02-account', '04-workspace'}}
    keys.update({'05-permissions': 'databricks/dev/demo/05-permissions.tfstate',
                 ROOT: f'databricks/dev/demo/{ROOT}.tfstate'})
    backend = {'bucket': args.state_bucket, 'region': args.state_region, 'key': keys[ROOT]}
    plan = args.artifacts.resolve() / 'terraform.tfplan'
    metadata = args.artifacts.resolve() / 'manifest.json'
    with tempfile.TemporaryDirectory(prefix='databricks-entitlements-') as temporary:
        temporary = Path(temporary)
        states = {root: read_state(args.state_bucket, key, args.state_region, temporary) for root, key in keys.items()}
        if args.action == 'destroy':
            require(not managed(states['04-workspace'] or {}),
                    'Retire root04 compute before workspace entitlements')
        empty = retirement and not managed(states[ROOT] or {})
        values = None if empty else bind_values(bundle, intent, states['02-account'])
        if values:
            check_ownership(values, states)
        binding = {'version': 1, 'operation': 'retire-entitlements' if retirement else 'workspace-entitlements',
                   'commit': provision.capture(['git', '-C', str(FOUNDATION), 'rev-parse', 'HEAD']),
                   'source_digest': source_digest(), 'intent': intent, 'inputs': values, 'backend': backend,
                   'states': {root: digest(state) for root, state in states.items()}, 'noop': empty}
        if applying:
            check_saved_plan(json.loads(metadata.read_text()), binding, plan.read_bytes())
        else:
            require(not metadata.exists() and not plan.exists(), 'Artifacts already contain a plan; choose a fresh directory')
        if empty:
            if not applying:
                plan.write_bytes(b'no-owned-workspace-entitlements\n')
                save_manifest(metadata, binding, plan.read_bytes())
            print('Workspace access state has no managed resources; no entitlement retirement required.')
            return
        preflight(values, intent)
        checkout = temporary / 'foundation'
        for folder in ('modules', f'environments/dev/{ROOT}'):
            shutil.copytree(FOUNDATION / folder, checkout / folder, ignore=provision.ignore)
        root = checkout / 'environments/dev' / ROOT
        variables = temporary / 'workspace-access.tfvars.json'
        variables.write_text(json.dumps(values, sort_keys=True))
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
        check_plan(document, retirement)
        if applying:
            provision.run(['terraform', 'apply', '-input=false', '-lock-timeout=60s', str(plan)], root)
        else:
            save_manifest(metadata, binding, plan.read_bytes())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('render', 'check-approval', 'plan', 'apply', 'preview-destroy', 'destroy'))
    parser.add_argument('--environment', default='dev')
    parser.add_argument('--workspace', default='demo')
    parser.add_argument('--state-bucket')
    parser.add_argument('--state-region')
    parser.add_argument('--confirm-environment')
    parser.add_argument('--artifacts', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        execute(args)
    except (ConfigError, EnvironmentConfigError, IdentityCheckError) as exc:
        print(f'Workspace feature execution blocked: {exc}', file=sys.stderr)
        return 1
    except Exception as exc:
        print(f'Workspace feature execution failed ({type(exc).__name__}); SDK details are redacted', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
