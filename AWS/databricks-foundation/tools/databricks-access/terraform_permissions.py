#!/usr/bin/env python3
"""Validate YAML, render permission-only Terraform inputs, plan or apply a bound plan."""
import argparse
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from configuration import ConfigError, FOUNDATION, load_bundle, require
from desired import preview
from identity_check import IdentityCheckError, verify_identity

sys.path.insert(0, str(FOUNDATION / 'tools/environment'))
import terraform_environment as provision
from deprovision_environment import managed, read_state
from environment import ConfigError as EnvironmentConfigError, load, state_keys, validate

ROOT = '05-permissions'
WORKSPACE_ACCESS_ROOT = '02-workspace-access'
ALLOWED_TYPES = {'databricks_group', 'databricks_mws_permission_assignment',
                 'databricks_entitlements', 'databricks_grant'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def render(bundle):
    desired = preview(bundle)
    target = bundle['target']
    names = {group['display_name']: key for key, group in desired['groups'].items()}
    return {
        **{key: target[key] for key in ('account_id', 'workspace_url', 'metastore_id')},
        'workspace_id': int(target['workspace_id']),
        'groups': {key: {field: group[field] for field in
                        ('display_name', 'lifecycle', 'workspace_role', 'entitlements', 'account_group_id')
                        if field in group} for key, group in desired['groups'].items()},
        'grants': {json.dumps([grant['object_type'], grant['object_name'], grant['principal']], separators=(',', ':')): {
            'object_type': grant['object_type'], 'object_name': grant['object_name'],
            'group_key': names[grant['principal']], 'privileges': grant['privileges']
        } for grant in desired['grants']},
    }


def identity(values):
    return {key: str(values[key]) for key in ('account_id', 'workspace_id', 'workspace_url', 'metastore_id')}


def instances(state, kind):
    return [instance['attributes'] for resource in managed(state or {}) if resource['type'] == kind
            for instance in resource['instances'] if not instance.get('deposed')]


def grant_scope(attributes):
    return next(((kind, attributes[kind]) for kind in ('catalog', 'schema', 'table')
                 if attributes.get(kind)), None)


def check_workspace_outputs(values, state):
    outputs = (state or {}).get('outputs', {})
    require(str(outputs.get('workspace_id', {}).get('value')) == str(values['workspace_id']) and
            outputs.get('workspace_url', {}).get('value') == values['workspace_url'],
            'Root 02 provisioning outputs do not match the registered workspace; review the target/backend')


def bind_bootstrap_groups(values, state):
    """Bind Terraform-owned references only to verified root 02 resources and outputs."""
    bound = copy.deepcopy(values)
    outputs = (state or {}).get('outputs', {}).get('account_group_ids', {}).get('value', {})
    require(isinstance(outputs, dict), 'Root 02 account_group_ids output must be a map')
    seen = set()
    for group in bound['groups'].values():
        if group['lifecycle'] != 'terraform':
            continue
        name = group['display_name']
        group_id = outputs.get(name)
        require(isinstance(group_id, str) and group_id.isascii() and group_id.isdigit() and
                int(group_id) > 0 and group_id not in seen,
                f'Root 02 has no unique numeric account_group_ids binding: {name}')
        seen.add(group_id)
        require(not group.get('account_group_id') or group['account_group_id'] == group_id,
                f'Root 02 group ID differs from the reviewed reference: {name}')
        matches = [item for item in instances(state, 'databricks_group')
                   if item.get('display_name') == name or str(item.get('id')) == group_id]
        require(len(matches) == 1 and matches[0].get('display_name') == name and
                str(matches[0].get('id')) == group_id,
                f'Root 02 managed group does not match its output: {name}')
        assignments = [item for item in instances(state, 'databricks_mws_permission_assignment')
                       if str(item.get('workspace_id')) == str(values['workspace_id']) and
                       str(item.get('principal_id')) == group_id]
        require(len(assignments) == 1 and assignments[0].get('permissions') == [group['workspace_role']],
                f'Root 02 workspace assignment does not match the expected role: {name}')
        group['account_group_id'] = group_id
    return bound


def check_ownership(values, states, supplemental):
    verified = bind_bootstrap_groups(values, states.get('02-account'))
    bootstrap = {group['display_name']: group for group in verified['groups'].values()
                 if group['lifecycle'] == 'terraform'}
    require(all(values['groups'][key].get('account_group_id') == group['account_group_id']
                for key, group in verified['groups'].items() if group['lifecycle'] == 'terraform'),
            'Terraform bootstrap references must be bound before ownership validation')
    bootstrap_ids = {group['account_group_id'] for group in bootstrap.values()}
    names = {group['display_name'] for group in values['groups'].values()}
    group_ids = {group['account_group_id'] for group in values['groups'].values() if group.get('account_group_id')}
    group_ids.update(group['id'] for group in instances(states.get(ROOT), 'databricks_group')
                     if group.get('display_name') in names)
    scopes = {(grant['object_type'], grant['object_name']) for grant in values['grants'].values()}
    pairs = {(grant['object_type'], grant['object_name'], values['groups'][grant['group_key']]['display_name'])
             for grant in values['grants'].values()}
    configured = supplemental.get('account_groups', {})
    require(all(name in configured and configured[name].get('workspace_permission', 'USER') == group['workspace_role']
                for name, group in bootstrap.items()),
            'Root 02 supplemental bootstrap groups must match their registered workspace roles')
    require(not (names - bootstrap.keys()).intersection(configured),
            'Permission groups overlap platform/terraform-inputs root 02 account_groups')
    for root, state in states.items():
        if root == WORKSPACE_ACCESS_ROOT and managed(state or {}):
            outputs = state.get('outputs', {})
            expected_target = {'environment': 'dev', 'workspace': 'demo',
                               **{key: str(values[key]) for key in ('account_id', 'workspace_id', 'workspace_url')}}
            require(outputs.get('target_identity', {}).get('value') == expected_target
                    and outputs.get('group_ids', {}).get('value') == {
                        key: group['account_group_id'] for key, group in verified['groups'].items()
                        if group['lifecycle'] == 'terraform'},
                    'Workspace feature state must match the verified bootstrap target and group IDs')
            require(all(resource['type'] == 'databricks_entitlements' for resource in managed(state)),
                    'Workspace feature state contains unexpected resource ownership')
            require(all(str(item.get('group_id')) in bootstrap_ids
                        for item in instances(state, 'databricks_entitlements')),
                    'Workspace feature state contains unexpected group ownership')
        if root == ROOT:
            require(not any(group.get('display_name') in bootstrap or str(group.get('id')) in bootstrap_ids
                            for group in instances(state, 'databricks_group')),
                    'Bootstrap group is still owned by 05-permissions; review ownership migration')
            require(not any(str(item.get('principal_id')) in bootstrap_ids
                            for item in instances(state, 'databricks_mws_permission_assignment')),
                    'Bootstrap workspace assignment is still owned by 05-permissions; review ownership migration')
            require(not any(str(item.get('group_id')) in bootstrap_ids
                            for item in instances(state, 'databricks_entitlements')),
                    'Bootstrap entitlements are still owned by 05-permissions; keep entitlements deferred')
            bound = (state or {}).get('outputs', {}).get('target_identity', {}).get('value')
            require(not managed(state or {}) or bound == identity(values),
                    'Existing permissions state is bound to a different or unknown target')
            continue
        for group in instances(state, 'databricks_group'):
            allowed = root == '02-account' and group.get('display_name') in bootstrap and str(group.get('id')) in bootstrap_ids
            require(allowed or (group.get('display_name') not in names and str(group.get('id')) not in group_ids),
                    f'Group is already owned by {root}')
        for assignment in instances(state, 'databricks_mws_permission_assignment'):
            allowed = (root == '02-account' and str(assignment.get('workspace_id')) == str(values['workspace_id']) and
                       any(str(assignment.get('principal_id')) == group['account_group_id'] and
                           assignment.get('permissions') == [group['workspace_role']] for group in bootstrap.values()))
            require(allowed or str(assignment.get('workspace_id')) != str(values['workspace_id']) or
                    str(assignment.get('principal_id')) not in group_ids,
                    f'Workspace assignment is already owned by {root}')
        for entitlements in instances(state, 'databricks_entitlements'):
            if root == WORKSPACE_ACCESS_ROOT and str(entitlements.get('group_id')) in bootstrap_ids:
                continue
            require(str(entitlements.get('group_id')) not in group_ids,
                    f'Group entitlements are already owned by {root}')
        for grant in instances(state, 'databricks_grants'):
            require(grant_scope(grant) not in scopes, f'Whole-object ACL is already owned by {root}')
        for grant in instances(state, 'databricks_grant'):
            scope = grant_scope(grant)
            require(not scope or (*scope, grant.get('principal')) not in pairs,
                    f'Principal/object grant is already owned by {root}')


def preflight(values, state):
    from databricks.sdk import AccountClient, WorkspaceClient
    from databricks.sdk.service.catalog import SecurableType
    credentials = dict(auth_type='oauth-m2m', client_id=os.environ['DATABRICKS_CLIENT_ID'],
                       client_secret=os.environ['DATABRICKS_CLIENT_SECRET'])
    account = AccountClient(host='https://accounts.cloud.databricks.com', account_id=values['account_id'], **credentials)
    workspace = WorkspaceClient(host=values['workspace_url'], **credentials)
    for line in verify_identity(account, workspace, values['account_id'], str(values['workspace_id']), values['workspace_url']):
        print(line, flush=True)
    assignment = workspace.metastores.current()
    require(str(assignment.workspace_id) == str(values['workspace_id']) and assignment.metastore_id == values['metastore_id'],
            'Live metastore assignment does not match the registered target')
    owned_groups = {group['id'] for group in instances(state, 'databricks_group')}
    for group in values['groups'].values():
        found = list(account.groups.list(filter=f'displayName eq "{group["display_name"]}"'))
        if group['lifecycle'] in {'external', 'terraform'}:
            require(group.get('account_group_id') and len(found) == 1 and found[0].id == group['account_group_id'],
                    f'{group["lifecycle"].capitalize()} group identity mismatch: {group["display_name"]}')
        else:
            require(not found or (len(found) == 1 and found[0].id in owned_groups),
                    f'Existing group requires reviewed import: {group["display_name"]}')
    owned = {(*grant_scope(grant), grant['principal']) for grant in instances(state, 'databricks_grant')
             if grant_scope(grant)}
    by_scope = {}
    for grant in values['grants'].values():
        scope = (grant['object_type'], grant['object_name'])
        by_scope.setdefault(scope, set()).add(values['groups'][grant['group_key']]['display_name'])
    for (kind, name), principals in sorted(by_scope.items()):
        try:
            {'catalog': workspace.catalogs.get, 'schema': workspace.schemas.get, 'table': workspace.tables.get}[kind](name)
            grants = workspace.grants.get(getattr(SecurableType, kind.upper()), name)
        except Exception as exc:
            raise ConfigError(f'Cannot read existing {kind} {name} ({type(exc).__name__}); create/authorize it outside this workflow') from None
        for grant in grants.privilege_assignments or []:
            require(grant.principal not in principals or not grant.privileges or (kind, name, grant.principal) in owned,
                    f'Existing direct grant requires reviewed import: {kind} {name} / {grant.principal}')
    print('Existing objects and permissions ownership preflight: PASS', flush=True)


def check_plan(plan):
    for change in plan.get('resource_changes', []):
        if change['mode'] != 'managed':
            continue
        require(change['type'] in ALLOWED_TYPES, f'Plan contains forbidden resource type: {change["type"]}')
        actions = change['change']['actions']
        require('delete' not in actions or change['type'] == 'databricks_grant',
                'Group, assignment or entitlement deletion/replacement requires separate retirement review')
        if change['type'] == 'databricks_mws_permission_assignment':
            before, after = change['change'].get('before') or {}, change['change'].get('after') or {}
            require('ADMIN' not in before.get('permissions', []) or 'ADMIN' in after.get('permissions', []),
                    'Workspace ADMIN removal requires a separate migration')


def require_environment_protection(environment):
    """Read-only prerequisite shared by preflight and the actual apply gate."""
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    require(repository and os.environ.get('GH_TOKEN'), 'Apply requires trusted GitHub context')
    protection = json.loads(subprocess.check_output(
        ['gh', 'api', f'repos/{repository}/environments/{environment}'], text=True))
    require(not protection.get('can_admins_bypass', True) and
            any(rule.get('type') == 'required_reviewers' and rule.get('reviewers') and rule.get('prevent_self_review')
                for rule in protection.get('protection_rules', [])),
            f'{environment} must require reviewers with self-review and administrator bypass disabled before apply. '
            f'Configure https://github.com/{repository}/settings/environments, then start a fresh provisioning run; '
            'the apply opt-in alone does not configure approval protection.')


def require_apply_gate(environment, opt_in='DATABRICKS_PERMISSIONS_APPLY_ENABLED'):
    require(os.environ.get('GITHUB_REF') == 'refs/heads/main', 'Apply is allowed only on main')
    require(os.environ.get(opt_in) == 'true', f'Apply requires {opt_in}=true')
    require_environment_protection(environment)


def check_saved_plan(saved, expected, plan_bytes, now=None):
    require(saved['binding'] == expected and saved['plan_sha256'] == hashlib.sha256(plan_bytes).hexdigest(),
            'Plan, source, inputs or ownership changed; create a fresh plan')
    require((now or datetime.now(timezone.utc)) < datetime.fromisoformat(saved['expires_at']),
            'Plan expired; create a fresh plan')


def source_digest():
    paths = set()
    for folder in ('platform', 'workloads', 'tools/databricks-access', 'tools/environment', 'modules/databricks',
                   f'environments/dev/{ROOT}'):
        paths.update(path for path in (FOUNDATION / folder).rglob('*') if path.is_file()
                     and path.suffix in {'.py', '.tf', '.hcl', '.yaml', '.json', '.txt'}
                     and not any(part in {'.terraform', '__pycache__', 'tests'} for part in path.parts)
                     and not path.name.endswith(('.tfvars', '.tfvars.json')))
    return digest({str(path.relative_to(FOUNDATION)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)})


def execute(args):
    require(not any(key.startswith(('TF_VAR_', 'TF_CLI_ARGS')) or key in
                    {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'} for key in os.environ),
            'Remove Terraform environment overrides before running')
    bundle = load_bundle()
    values = render(bundle)
    if args.action == 'render':
        args.artifacts.mkdir(parents=True, exist_ok=True)
        (args.artifacts / 'permissions.tfvars.json').write_text(json.dumps(values, indent=2, sort_keys=True) + '\n')
        print('Rendered permission-only inputs; compute declarations are not deployed.')
        return
    require(bundle['target']['active'], 'Activate a verified target before live planning')
    require(args.state_bucket and args.state_region, 'State bucket and region are required')
    require(os.environ.get('DATABRICKS_ACCOUNT_ID') == values['account_id'], 'CI account must match the registered target')
    require(os.environ.get('DATABRICKS_CLIENT_ID') and os.environ.get('DATABRICKS_CLIENT_SECRET'), 'OAuth M2M credentials are required')
    if args.action == 'apply':
        require_apply_gate('dev-demo-apply')
    config = validate(load(FOUNDATION / 'platform/environments/dev/demo.yaml'))
    provision.check_identity(config)
    keys = state_keys(config) | {ROOT: 'databricks/dev/demo/05-permissions.tfstate',
                                 WORKSPACE_ACCESS_ROOT: f'databricks/dev/demo/{WORKSPACE_ACCESS_ROOT}.tfstate'}
    backend = {'bucket': args.state_bucket, 'region': args.state_region, 'key': keys[ROOT]}
    args.artifacts.mkdir(parents=True, exist_ok=True)
    plan = args.artifacts.resolve() / 'terraform.tfplan'
    metadata = args.artifacts.resolve() / 'manifest.json'
    with tempfile.TemporaryDirectory(prefix='databricks-permissions-') as temporary:
        temporary = Path(temporary)
        states = {root: read_state(args.state_bucket, key, args.state_region, temporary)
                  for root, key in keys.items() if root != '01-infra'}
        check_workspace_outputs(values, states['02-account'])
        values = bind_bootstrap_groups(values, states['02-account'])
        supplemental = json.loads((FOUNDATION / 'platform/terraform-inputs/dev/demo.02-account.json').read_text())
        check_ownership(values, states, supplemental)
        expected = {'version': 1, 'commit': provision.capture(['git', '-C', str(FOUNDATION), 'rev-parse', 'HEAD']),
                    'source_digest': source_digest(), 'inputs': values, 'backend': backend,
                    'legacy_states': {root: digest(state) for root, state in states.items() if root != ROOT}}
        if args.action == 'apply':
            saved = json.loads(metadata.read_text())
            check_saved_plan(saved, expected, plan.read_bytes())
        preflight(values, states[ROOT])
        checkout = temporary / 'foundation'
        for folder in ('modules', f'environments/dev/{ROOT}'):
            shutil.copytree(FOUNDATION / folder, checkout / folder, ignore=provision.ignore)
        root = checkout / 'environments/dev' / ROOT
        variables = temporary / 'permissions.tfvars.json'
        variables.write_text(json.dumps(values, sort_keys=True))
        backend_file = temporary / 'backend.hcl'
        backend_file.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in backend.items()) + '\nuse_lockfile = true\nencrypt = true\n')
        provision.run(['terraform', 'init', '-input=false', '-lockfile=readonly', f'-backend-config={backend_file}'], root)
        provision.run(['terraform', 'validate'], root)
        if args.action == 'plan':
            provision.run(['terraform', 'plan', '-input=false', '-lock-timeout=60s', f'-var-file={variables}', f'-out={plan}'], root)
            document = json.loads(subprocess.check_output(['terraform', 'show', '-json', str(plan)], cwd=root, text=True))
            check_plan(document)
            metadata.write_text(json.dumps({'binding': expected, 'plan_sha256': hashlib.sha256(plan.read_bytes()).hexdigest(),
                                            'expires_at': (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()}, indent=2, sort_keys=True))
        else:
            document = json.loads(subprocess.check_output(['terraform', 'show', '-json', str(plan)], cwd=root, text=True))
            check_plan(document)
            provision.run(['terraform', 'apply', '-input=false', '-lock-timeout=60s', str(plan)], root)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('render', 'plan', 'apply'))
    parser.add_argument('--state-bucket')
    parser.add_argument('--state-region')
    parser.add_argument('--artifacts', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        execute(args)
    except (ConfigError, EnvironmentConfigError, IdentityCheckError) as exc:
        print(f'Permissions execution blocked: {exc}', file=sys.stderr)
        return 1
    except Exception as exc:
        print(f'Permissions execution failed ({type(exc).__name__}); SDK details are redacted', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
