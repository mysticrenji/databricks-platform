#!/usr/bin/env python3
"""Run one existing Terraform root in an isolated copy using validated inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from environment import ConfigError, ROOTS, check_target, load, render, state_keys, validate

FOUNDATION = Path(__file__).resolve().parents[2]
# Compatibility inputs deliberately remain platform-owned, outside persona YAML.
EXTRAS = {
    '01-infra': {'enable_observability_bucket', 'observability_bucket_name', 'kinesis_stream', 'observability_alarm_action_arns', 'observability_s3_request_metrics', 'observability_ebs_volume_ids'},
    '02-account': {'account_groups', 'monthly_budget_usd', 'budget_alert_email_addresses', 'budget_alert_threshold_percentages'},
}
RUNNABLE_ENVIRONMENTS = ('dev', 'staging')


def run(command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def capture(command):
    return subprocess.check_output(command, text=True).strip()


def require_demo_apply(confirmation, *, destroy=False):
    """Authorize dev/demo saved-plan execution; dataset permissions stay separate."""
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise ConfigError('Demo execution requires a manual workflow_dispatch run on main')
    if confirmation != 'dev/demo':
        raise ConfigError('Demo execution requires matching --confirm-environment dev/demo')
    opt_in = 'ENVIRONMENT_YAML_DESTROY_ENABLED' if destroy else 'ENVIRONMENT_YAML_APPLY_ENABLED'
    if os.environ.get(opt_in) != 'true':
        raise ConfigError(f'Demo execution requires {opt_in}=true')
    repository, actor = os.environ.get('GITHUB_REPOSITORY'), os.environ.get('GITHUB_ACTOR')
    if not repository or not actor or not os.environ.get('GH_TOKEN'):
        raise ConfigError('Demo execution requires trusted GitHub repository, actor and token context')
    for user in {actor, os.environ.get('GITHUB_TRIGGERING_ACTOR', actor)}:
        permission = json.loads(capture(['gh', 'api', f'repos/{repository}/collaborators/{user}/permission']))
        if permission.get('permission') != 'admin':
            raise ConfigError('Demo execution must be started and rerun by a repository administrator')


def inputs(config, root, state_bucket, state_region, infra_state_key):
    values = render(config)[root]
    path = FOUNDATION / f'platform/terraform-inputs/{config["environment"]["name"]}/{config["workspace"]["name"]}.{root}.json'
    extras = json.loads(path.read_text())
    if not isinstance(extras, dict) or set(extras) - EXTRAS[root]:
        raise ConfigError(f'{path.name}: unsupported supplemental input')
    values.update(extras)
    if root == '02-account':
        values.update(state_bucket=state_bucket, state_region=state_region, infra_state_key=infra_state_key)
    return values


def check_identity(config):
    env = config['environment']
    if os.environ.get('EXPECTED_DEPLOYMENT_ROLE_ARN') != env['deployment_role_arn']:
        raise ConfigError('YAML role must match trusted EXPECTED_DEPLOYMENT_ROLE_ARN')
    if os.environ.get('DATABRICKS_ACCOUNT_ID') != config['databricks']['account_id']:
        raise ConfigError('YAML Databricks account must match trusted DATABRICKS_ACCOUNT_ID')
    identity = json.loads(capture(['aws', 'sts', 'get-caller-identity', '--output', 'json']))
    role_name = env['deployment_role_arn'].rsplit('/', 1)[1]
    if identity['Account'] != env['aws_account_id'] or not identity['Arn'].startswith(f'arn:aws:sts::{identity["Account"]}:assumed-role/{role_name}/'):
        raise ConfigError('Effective AWS identity is not the configured deployment role/account')


def ignore(directory, names):
    return [name for name in names if name in {'.terraform', '.git', '__pycache__', 'backend.hcl'} or name.endswith(('.tfvars', '.tfvars.json', '.tfstate', '.tfplan')) or '.tfstate.' in name]


def manifest(config, root, values, backend):
    # Include all tracked/untracked source bytes used in the isolated run; exclude
    # local inputs and generated state. Git commit also binds the CI source ref.
    digest = hashlib.sha256()
    for folder in ('modules', 'environments/dev'):
        for path in sorted((FOUNDATION / folder).rglob('*')):
            if path.is_file() and (path.suffix == '.tf' or path.name == '.terraform.lock.hcl') and '.terraform' not in path.parts:
                digest.update(str(path.relative_to(FOUNDATION)).encode())
                digest.update(path.read_bytes())
    for path in sorted(Path(__file__).parent.glob('*')):
        if path.suffix in {'.py', '.json', '.txt'}:
            digest.update(path.name.encode())
            digest.update(path.read_bytes())
    return {
        'root': root,
        'commit': capture(['git', '-C', str(FOUNDATION), 'rev-parse', 'HEAD']),
        'source_digest': digest.hexdigest(),
        'config': config,
        'inputs': values,
        'backend': backend,
    }


def execute(args):
    config = validate(load(args.config))
    if config['environment']['name'] not in RUNNABLE_ENVIRONMENTS:
        raise ConfigError('The Terraform runner supports only dev and staging; production is configuration-only.')
    check_target(config)
    if any(key.startswith('TF_VAR_') or key.startswith('TF_CLI_ARGS') or key in {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'} for key in os.environ):
        raise ConfigError('Remove Terraform variable/CLI/data/workspace/config overrides before running')
    if args.root not in ROOTS:
        raise ConfigError('Only infrastructure and workspace-creation roots are supported')
    values = inputs(config, args.root, args.state_bucket, args.state_region, args.infra_state_key)
    keys = {'01-infra': args.infra_state_key, '02-account': args.account_state_key}
    if any(key != state_keys(config)[root] for root, key in keys.items()):
        raise ConfigError('State keys must match the selected environment/workspace namespace')
    if not all((args.state_bucket, args.state_region, args.infra_state_key, args.account_state_key)):
        raise ConfigError('State bucket, region and both keys must be non-empty')
    if args.infra_state_key == args.account_state_key:
        raise ConfigError('Infrastructure and account states must use distinct keys')
    if args.action == 'apply' and os.environ.get('ENVIRONMENT_YAML_APPLY_ENABLED') != 'true':
        raise ConfigError('Apply requires ENVIRONMENT_YAML_APPLY_ENABLED=true after backend/input review')
    if args.action == 'apply' and (config['environment']['name'], config['workspace']['name']) == ('dev', 'demo'):
        require_demo_apply(args.confirm_environment)
    backend = {'bucket': args.state_bucket, 'region': args.state_region, 'key': keys[args.root]}
    check_identity(config)
    expected = manifest(config, args.root, values, backend)
    expected['yaml_sha256'] = hashlib.sha256(args.config.read_bytes()).hexdigest()
    if args.root == '02-account':
        upstream = json.loads(capture(['aws', 's3api', 'head-object', '--bucket', args.state_bucket, '--key', args.infra_state_key, '--region', args.state_region, '--output', 'json']))
        expected['upstream_state'] = {key: upstream.get(key) for key in ('ETag', 'VersionId', 'ContentLength', 'LastModified')}
    args.artifacts.mkdir(parents=True, exist_ok=True)
    plan = args.artifacts.resolve() / 'terraform.tfplan'
    metadata = args.artifacts.resolve() / 'manifest.json'
    if args.action == 'apply':
        saved = json.loads(metadata.read_text())
        if saved != expected | {'plan_sha256': hashlib.sha256(plan.read_bytes()).hexdigest()}:
            raise ConfigError('Plan, source or inputs changed; create and review a new plan')
    with tempfile.TemporaryDirectory(prefix='databricks-environment-') as temporary:
        checkout = Path(temporary) / 'foundation'
        for folder in ('modules', 'environments/dev'):
            shutil.copytree(FOUNDATION / folder, checkout / folder, ignore=ignore)
        root = checkout / 'environments/dev' / args.root
        variable_file = Path(temporary) / 'inputs.json'
        variable_file.write_text(json.dumps(values, sort_keys=True))
        backend_file = Path(temporary) / 'backend.hcl'
        backend_file.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in expected['backend'].items()) + '\nuse_lockfile = true\nencrypt = true\n')
        run(['terraform', 'init', '-input=false', '-lockfile=readonly', f'-backend-config={backend_file}'], root)
        run(['terraform', 'validate'], root)
        if args.action == 'plan':
            run(['terraform', 'plan', '-input=false', f'-var-file={variable_file}', f'-out={plan}'], root)
            expected['plan_sha256'] = hashlib.sha256(plan.read_bytes()).hexdigest()
            metadata.write_text(json.dumps(expected, indent=2, sort_keys=True) + '\n')
        else:
            run(['terraform', 'apply', '-input=false', str(plan)], root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'apply'))
    parser.add_argument('config', type=Path)
    parser.add_argument('--root', required=True, choices=ROOTS)
    parser.add_argument('--state-bucket', required=True)
    parser.add_argument('--state-region', required=True)
    parser.add_argument('--infra-state-key', required=True)
    parser.add_argument('--account-state-key', required=True)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--confirm-environment')
    args = parser.parse_args()
    try:
        execute(args)
    except (ConfigError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'Environment execution failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
