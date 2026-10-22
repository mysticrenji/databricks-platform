#!/usr/bin/env python3
"""Deprovision a root, retaining storage by default or explicitly purging S3 afterward."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import terraform_environment as provision
import storage_cleanup
from environment import ConfigError, ROOTS, check_target, load, state_keys, validate


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def managed(state):
    return [resource for resource in state.get('resources', [])
            if resource['mode'] == 'managed' and resource.get('instances')]


def retained_addresses(state):
    addresses = []
    for resource in managed(state):
        if resource['type'].startswith(('aws_s3_', 'aws_kms_')):
            prefix = resource.get('module', '')
            address = '.'.join(filter(None, (prefix, resource['type'], resource['name'])))
            for instance in resource['instances']:
                suffix = f'[{json.dumps(instance["index_key"])}]' if 'index_key' in instance else ''
                addresses.append(address + suffix)
    return sorted(addresses)


def read_state(bucket, key, region, folder):
    path = folder / (hashlib.sha256(key.encode()).hexdigest() + '.json')
    result = subprocess.run(
        ['aws', 's3api', 'get-object', '--bucket', bucket, '--key', key,
         '--region', region, str(path)], capture_output=True, text=True,
    )
    if result.returncode:
        if '(NoSuchKey)' in result.stderr or '(404)' in result.stderr:
            return None
        raise ConfigError(f'Cannot read state {key}: {result.stderr.strip()}')
    state = json.loads(path.read_text())
    if state.get('version') != 4 or not isinstance(state.get('resources'), list):
        raise ConfigError(f'{key}: unsupported Terraform state format')
    return state


def plan_changes(plan, root):
    output = subprocess.check_output(['terraform', 'show', '-json', str(plan)], cwd=root, text=True)
    changes = json.loads(output).get('resource_changes', [])
    # Output metadata and plan timestamps are not a resource deletion contract.
    return sorted([change for change in changes if change['mode'] == 'managed'], key=lambda c: c['address'])


def require_destroy_only(changes):
    for change in changes:
        if change['change']['actions'] not in (['delete'], ['no-op']):
            raise ConfigError('Destroy preview contains an unexpected resource action')
        if change['type'].startswith(('aws_s3_', 'aws_kms_')) and change['change']['actions'] != ['no-op']:
            raise ConfigError('Destroy preview would delete retained storage or KMS resources')


def execute(args):
    config = validate(load(args.config))
    target = config['environment']['name']
    if target not in provision.RUNNABLE_ENVIRONMENTS or os.environ.get('TARGET_ENVIRONMENT', target) != target:
        raise ConfigError('Only the selected dev or staging environment can be deprovisioned')
    check_target(config)
    if any(key.startswith(('TF_VAR_', 'TF_CLI_ARGS')) or key in
           {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'} for key in os.environ):
        raise ConfigError('Remove Terraform environment overrides before running')
    if args.action == 'destroy' and (
        args.confirm_environment != f'{target}/{config["workspace"]["name"]}' or os.environ.get('ENVIRONMENT_YAML_DESTROY_ENABLED') != 'true'
    ):
        raise ConfigError('Destroy requires matching --confirm-environment and ENVIRONMENT_YAML_DESTROY_ENABLED=true')
    purge_storage = getattr(args, 'purge_storage', False)
    if purge_storage and args.action == 'destroy' and (
        getattr(args, 'confirm_purge_storage', '') != f'{target}/{config["workspace"]["name"]}'
    ):
        raise ConfigError('Storage purge requires matching --confirm-purge-storage environment/workspace')
    if args.action == 'destroy' and (target, config['workspace']['name']) == ('dev', 'demo'):
        provision.require_demo_apply(args.confirm_environment, destroy=True)
    keys = {'01-infra': args.infra_state_key, '02-account': args.account_state_key,
            '03-data-access': args.data_access_state_key, '04-workspace': args.workspace_state_key}
    if not args.state_bucket or not args.state_region or not all(keys.values()) or len(set(keys.values())) != 4:
        raise ConfigError('Provide the state bucket/region and four distinct, explicit state keys')
    if keys != state_keys(config):
        raise ConfigError('State keys must match the selected environment/workspace namespace')
    # Permissions have a separate owner; never remove its workspace underneath it.
    keys['05-permissions'] = f'databricks/{target}/{config["workspace"]["name"]}/05-permissions.tfstate'
    keys['02-workspace-access'] = f'databricks/{target}/{config["workspace"]["name"]}/02-workspace-access.tfstate'
    provision.check_identity(config)
    values = provision.inputs(config, args.root, args.state_bucket, args.state_region, args.infra_state_key)
    backend = {'bucket': args.state_bucket, 'region': args.state_region, 'key': keys[args.root]}
    args.artifacts.mkdir(parents=True, exist_ok=True)
    artifacts = args.artifacts.resolve()

    with tempfile.TemporaryDirectory(prefix='databricks-destroy-') as temporary:
        temporary = Path(temporary)
        states = {name: read_state(args.state_bucket, key, args.state_region, temporary)
                  for name, key in keys.items()}
        for name in ('03-data-access', '04-workspace', '05-permissions', '02-workspace-access'):
            if states[name] and managed(states[name]):
                raise ConfigError(f'{name} still manages resources; deprovision it before roots 02 and 01')
        if args.root == '01-infra' and states['02-account'] and managed(states['02-account']):
            raise ConfigError('02-account must be empty before destroying 01-infra')
        retained = retained_addresses(states[args.root] or {})
        purge_inventory = []
        s3 = None
        if purge_storage and args.root == '01-infra':
            buckets = storage_cleanup.bucket_inventory(states[args.root], config, values, args.state_bucket)
            s3 = storage_cleanup.client(config['environment']['aws_region'])
            purge_inventory = storage_cleanup.inspect(s3, buckets, config['environment']['aws_account_id'],
                                                     config['environment']['aws_region'])
        expected = provision.manifest(config, args.root, values, backend) | {
            'operation': 'destroy-retain-storage', 'state_keys': keys,
            'states': {name: digest(state) for name, state in states.items()},
            'retained_addresses': retained,
            'purge_storage': purge_storage, 'purge_inventory_sha256': digest(purge_inventory),
        }
        metadata = artifacts / 'destroy-manifest.json'
        if args.action == 'destroy':
            saved = json.loads(metadata.read_text())
            if saved['binding'] != expected:
                raise ConfigError('Source, configuration, backend or state changed; create and review a new preview')
            if purge_inventory and json.loads((artifacts / 'purge-storage.json').read_text()) != purge_inventory:
                raise ConfigError('Storage purge inventory artifact changed; create and review a new preview')
            if digest(json.loads((artifacts / 'changes.json').read_text())) != saved['changes_sha256']:
                raise ConfigError('Destroy preview artifact changed; create and review a new preview')
            if states[args.root] and managed(states[args.root]):
                for name, state in states.items():
                    if digest(json.loads((artifacts / f'{name}.before.tfstate').read_text())) != digest(state):
                        raise ConfigError('State backup artifact changed; create and review a new preview')

        if not states[args.root] or not managed(states[args.root]):
            print(f'{args.root}: no managed resources; nothing to destroy')
            if args.action == 'preview':
                (artifacts / 'changes.json').write_text('[]\n')
                metadata.write_text(json.dumps({'binding': expected, 'changes_sha256': digest([])}, indent=2))
            return

        checkout = temporary / 'foundation'
        for folder in ('modules', 'environments/dev'):
            shutil.copytree(provision.FOUNDATION / folder, checkout / folder, ignore=provision.ignore)
        root = checkout / 'environments/dev' / args.root
        variables = temporary / 'inputs.json'
        variables.write_text(json.dumps(values))
        if args.action == 'preview':
            # Preview against a local copy: retention never mutates S3 state here.
            providers = root / 'providers.tf'
            source = providers.read_text()
            if source.count('backend "s3" {}') != 1:
                raise ConfigError('Expected one S3 backend declaration')
            providers.write_text(source.replace('backend "s3" {}', 'backend "local" {}'))
            (root / 'terraform.tfstate').write_text(json.dumps(states[args.root]))
            init = ['terraform', 'init', '-input=false', '-lockfile=readonly']
        else:
            backend_file = temporary / 'backend.hcl'
            backend_file.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in backend.items())
                                    + '\nuse_lockfile = true\nencrypt = true\n')
            init = ['terraform', 'init', '-input=false', '-lockfile=readonly', f'-backend-config={backend_file}']
        provision.run(init, root)
        provision.run(['terraform', 'validate'], root)
        print('Retaining S3 and KMS resource addresses: ' + json.dumps(retained), flush=True)

        if args.action == 'preview':
            # Uploaded before execution; these state backups contain sensitive data.
            for name, state in states.items():
                (artifacts / f'{name}.before.tfstate').write_text(json.dumps(state, indent=2))
            (artifacts / 'retained-addresses.json').write_text(json.dumps(retained, indent=2))
            if purge_inventory:
                (artifacts / 'purge-storage.json').write_text(json.dumps(purge_inventory, indent=2))
                print('PERMANENT storage purge after successful teardown: ' + json.dumps(purge_inventory), flush=True)
        if args.action == 'destroy':
            current = {name: read_state(args.state_bucket, key, args.state_region, temporary)
                       for name, key in keys.items()}
            if current != states:
                raise ConfigError('State changed during initialization; create and review a new preview')
        if retained:
            provision.run(['terraform', 'state', 'rm', '-lock-timeout=60s', *retained], root)
        plan = temporary / 'destroy.tfplan'
        provision.run(['terraform', 'plan', '-destroy', '-input=false', '-lock-timeout=60s',
                       f'-var-file={variables}', f'-out={plan}'], root)
        changes = plan_changes(plan, root)
        require_destroy_only(changes)
        if args.action == 'preview':
            (artifacts / 'changes.json').write_text(json.dumps(changes, indent=2, sort_keys=True))
            metadata.write_text(json.dumps({'binding': expected, 'changes_sha256': digest(changes)}, indent=2, sort_keys=True))
        else:
            if changes != json.loads((artifacts / 'changes.json').read_text()):
                raise ConfigError('Resource changes differ from approved preview; retained storage remains detached, review a fresh preview')
            provision.run(['terraform', 'destroy', '-input=false', '-auto-approve',
                           '-lock-timeout=60s', f'-var-file={variables}'], root)
            if purge_inventory:
                # Success from Terraform alone is insufficient; recheck every state.
                for name, key in keys.items():
                    state = read_state(args.state_bucket, key, args.state_region, temporary)
                    if state and managed(state):
                        raise ConfigError(f'{name} still manages resources; storage purge refused')
                storage_cleanup.purge(s3, buckets, config['environment']['aws_account_id'],
                                      config['environment']['aws_region'], purge_inventory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('preview', 'destroy'))
    parser.add_argument('config', type=Path)
    parser.add_argument('--root', required=True, choices=ROOTS)
    for field in ('state-bucket', 'state-region', 'infra-state-key', 'account-state-key',
                  'data-access-state-key', 'workspace-state-key'):
        parser.add_argument('--' + field, required=True)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--confirm-environment', default='')
    parser.add_argument('--purge-storage', action='store_true', help='Permanently delete reviewed S3 storage after infra destruction; never KMS/state bucket')
    parser.add_argument('--confirm-purge-storage', default='', help='Separate permanent-data-deletion confirmation: environment/workspace')
    try:
        execute(parser.parse_args())
    except (ConfigError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f'Deprovisioning failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
