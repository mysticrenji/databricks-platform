"""Exercise the real CLI with local stand-ins; no cloud resources are touched."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml
import test_environment
from test_environment import TOOLS
import terraform_environment as runner


class RunnerTests(unittest.TestCase):
    def test_demo_destroy_requires_its_own_opt_in_and_admin_context(self):
        trusted = {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                   'GITHUB_REPOSITORY': 'owner/repo', 'GITHUB_ACTOR': 'owner', 'GH_TOKEN': 'test',
                   'ENVIRONMENT_YAML_APPLY_ENABLED': 'true'}
        with patch.dict(os.environ, trusted, clear=True), \
             patch.object(runner, 'capture', return_value='{"permission": "admin"}') as api:
            with self.assertRaisesRegex(runner.ConfigError, 'ENVIRONMENT_YAML_DESTROY_ENABLED'):
                runner.require_demo_apply('dev/demo', destroy=True)
            api.assert_not_called()
            with patch.dict(os.environ, {'ENVIRONMENT_YAML_DESTROY_ENABLED': 'true',
                                         'ENVIRONMENT_YAML_APPLY_ENABLED': 'false'}):
                runner.require_demo_apply('dev/demo', destroy=True)
                for key, value in (('GITHUB_REF', 'refs/heads/feature'),
                                   ('GITHUB_EVENT_NAME', 'push'), ('GH_TOKEN', '')):
                    with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                        with self.assertRaises(runner.ConfigError):
                            runner.require_demo_apply('dev/demo', destroy=True)
                with self.assertRaises(runner.ConfigError):
                    runner.require_demo_apply('dev/other', destroy=True)
                api.return_value = '{"permission": "write"}'
                with self.assertRaisesRegex(runner.ConfigError, 'administrator'):
                    runner.require_demo_apply('dev/demo', destroy=True)

    def test_demo_apply_requires_manual_main_admin_opt_in_and_confirmation(self):
        trusted = {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                   'GITHUB_REPOSITORY': 'owner/repo', 'GITHUB_ACTOR': 'owner', 'GH_TOKEN': 'test',
                   'ENVIRONMENT_YAML_APPLY_ENABLED': 'true'}
        with patch.dict(os.environ, trusted, clear=True), \
             patch.object(runner, 'capture', return_value='{"permission": "admin"}') as api:
            runner.require_demo_apply('dev/demo')
            self.assertIn('repos/owner/repo/collaborators/owner/permission', api.call_args.args[0])
            for key, value in (('GITHUB_REF', 'refs/heads/feature'),
                               ('GITHUB_EVENT_NAME', 'push'), ('ENVIRONMENT_YAML_APPLY_ENABLED', 'false'),
                               ('GITHUB_REPOSITORY', ''), ('GITHUB_ACTOR', ''), ('GH_TOKEN', '')):
                with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                    with self.assertRaises(runner.ConfigError):
                        runner.require_demo_apply('dev/demo')
            for confirmation in ('', 'dev/shared', 'staging/demo'):
                with self.subTest(confirmation=confirmation), self.assertRaises(runner.ConfigError):
                    runner.require_demo_apply(confirmation)
            api.return_value = '{"permission": "write"}'
            with self.assertRaisesRegex(runner.ConfigError, 'administrator'):
                runner.require_demo_apply('dev/demo')
            api.return_value = '{"permission": "admin"}'
            with patch.dict(os.environ, {'GITHUB_TRIGGERING_ACTOR': 'other'}):
                api.side_effect = lambda command: json.dumps({'permission': 'write' if '/other/' in command[-1] else 'admin'})
                with self.assertRaisesRegex(runner.ConfigError, 'administrator'):
                    runner.require_demo_apply('dev/demo')

    def setUp(self):
        fixture = test_environment.EnvironmentTests()
        fixture.setUp()
        self.config = fixture.config
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.yaml = self.base / 'dev.yaml'
        self.yaml.write_text(yaml.safe_dump(self.config))
        self.artifacts = self.base / 'artifacts'
        self.log = self.base / 'commands.jsonl'
        binaries = self.base / 'bin'
        binaries.mkdir()
        aws = binaries / 'aws'
        aws.write_text('#!' + sys.executable + '\nimport json, os, sys\nif sys.argv[1] == "s3api":\n print(json.dumps({"ETag": os.environ.get("TEST_UPSTREAM_VERSION", "v1")})); sys.exit(0)\nprint(json.dumps({"Account": "123456789012", "Arn": os.environ.get("TEST_AWS_ARN", "arn:aws:sts::123456789012:assumed-role/deployer/session")}))\n')
        aws.chmod(0o755)
        terraform = binaries / 'terraform'
        terraform.write_text('''#!PYTHON
import json, os, pathlib, sys
args = sys.argv[1:]
cwd = pathlib.Path.cwd()
assert not list(cwd.glob('*.tfvars')), 'local tfvars leaked'
assert not list(cwd.glob('*.auto.tfvars.json')), 'automatic JSON leaked'
record = {'args': args, 'root': cwd.name}
if args[0] == 'plan':
    variables = next(a.split('=', 1)[1] for a in args if a.startswith('-var-file='))
    record['inputs'] = json.loads(pathlib.Path(variables).read_text())
    plan = next(a.split('=', 1)[1] for a in args if a.startswith('-out='))
    pathlib.Path(plan).write_bytes(b'saved plan')
with open(os.environ['TEST_COMMAND_LOG'], 'a') as output:
    output.write(json.dumps(record) + '\\n')
'''.replace('PYTHON', sys.executable))
        terraform.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(('TF_VAR_', 'TF_CLI_ARGS')) and key not in {'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_CLI_CONFIG_FILE'}}
        self.env.update(PATH=str(binaries) + os.pathsep + os.environ['PATH'], EXPECTED_DEPLOYMENT_ROLE_ARN=self.config['environment']['deployment_role_arn'], DATABRICKS_ACCOUNT_ID=self.config['databricks']['account_id'], TEST_COMMAND_LOG=str(self.log), ENVIRONMENT_YAML_APPLY_ENABLED='true')

    def invoke(self, action, root='01-infra', confirmation=''):
        keys = test_environment.environment.state_keys(self.config)
        return subprocess.run([sys.executable, str(TOOLS / 'terraform_environment.py'), action, str(self.yaml), '--root', root, '--state-bucket', 'acme-state', '--state-region', 'eu-west-1', '--infra-state-key', keys['01-infra'], '--account-state-key', keys['02-account'], '--confirm-environment', confirmation, '--artifacts', str(self.artifacts)], env=self.env, capture_output=True, text=True)

    def test_demo_cli_applies_saved_plan_only_with_manual_admin_confirmation(self):
        self.config['workspace']['name'] = 'demo'
        self.yaml.write_text(yaml.safe_dump(self.config))
        gh = self.base / 'bin/gh'
        gh.write_text('#!' + sys.executable + '\nprint(\'{"permission": "admin"}\')\n')
        gh.chmod(0o755)
        self.env.update(GITHUB_REF='refs/heads/main', GITHUB_EVENT_NAME='workflow_dispatch',
                        GITHUB_REPOSITORY='owner/repo', GITHUB_ACTOR='owner', GH_TOKEN='test')
        self.assertEqual(self.invoke('plan').returncode, 0)
        before = self.log.read_text()
        for confirmation in ('', 'dev/shared'):
            result = self.invoke('apply', confirmation=confirmation)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('confirm-environment dev/demo', result.stderr)
            self.assertEqual(self.log.read_text(), before)
        result = self.invoke('apply', confirmation='dev/demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(records[-1]['args'], ['apply', '-input=false', str(self.artifacts / 'terraform.tfplan')])

    def test_plan_and_apply_saved_plan_in_isolated_root(self):
        for action in ('plan', 'apply'):
            result = self.invoke(action)
            self.assertEqual(result.returncode, 0, result.stderr)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([r['args'][0] for r in records], ['init', 'validate', 'plan', 'init', 'validate', 'apply'])
        self.assertEqual(records[2]['inputs']['root_storage_bucket_name'], self.config['storage']['workspace_bucket_name'])
        self.assertNotIn('-auto-approve', records[-1]['args'])

    def test_account_root_receives_upstream_state_binding(self):
        result = self.invoke('plan', '02-account')
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.log.read_text().splitlines()[-1])
        self.assertEqual(record['inputs']['infra_state_key'], 'databricks/dev/shared/01-infra.tfstate')
        self.assertEqual(record['inputs']['state_bucket'], 'acme-state')

    def test_demo_ci_plans_four_groups_without_members_or_dataset_inputs(self):
        self.config['workspace']['name'] = 'demo'
        self.yaml.write_text(yaml.safe_dump(self.config))
        result = self.invoke('plan', '02-account')
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.log.read_text().splitlines()[-1])
        groups = record['inputs']['account_groups']
        self.assertEqual(set(groups), {f'dev-demo-{name}' for name in ('admins', 'engineers', 'analysts', 'ml')})
        for name, group in groups.items():
            self.assertEqual(group['workspace_permission'], 'ADMIN' if name.endswith('-admins') else 'USER')
            self.assertEqual(group['member_ids'], {})
            self.assertFalse(group.get('manager_group_names'))
        self.assertFalse({'catalogs', 'grants', 'cluster_policies', 'warehouses'} & record['inputs'].keys())

    def test_tampered_plan_is_rejected_before_terraform(self):
        self.assertEqual(self.invoke('plan').returncode, 0)
        (self.artifacts / 'terraform.tfplan').write_bytes(b'tampered')
        before = self.log.read_text()
        result = self.invoke('apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('create and review a new plan', result.stderr)
        self.assertEqual(self.log.read_text(), before)

    def test_changed_input_is_rejected_before_terraform(self):
        self.assertEqual(self.invoke('plan').returncode, 0)
        self.config['features']['observability'] = False
        self.yaml.write_text(yaml.safe_dump(self.config))
        result = self.invoke('apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('create and review a new plan', result.stderr)

    def test_untrusted_role_account_or_overrides_never_execute_terraform(self):
        for key, value in [('EXPECTED_DEPLOYMENT_ROLE_ARN', 'wrong'), ('DATABRICKS_ACCOUNT_ID', 'wrong'), ('TF_VAR_workspace_name', 'override'), ('TF_CLI_ARGS_plan', '-lock=false'), ('TEST_AWS_ARN', 'arn:aws:sts::123456789012:assumed-role/other/session')]:
            with self.subTest(key=key):
                previous = self.env.get(key)
                self.env[key] = value
                result = self.invoke('plan')
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.log.exists())
                if previous is None:
                    del self.env[key]
                else:
                    self.env[key] = previous

    def test_apply_is_disabled_until_inputs_and_backend_are_reviewed(self):
        self.assertEqual(self.invoke('plan').returncode, 0)
        self.env.pop('ENVIRONMENT_YAML_APPLY_ENABLED')
        before = self.log.read_text()
        result = self.invoke('apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('backend/input review', result.stderr)
        self.assertEqual(before, self.log.read_text())

    def test_invalid_yaml_never_executes_terraform(self):
        self.yaml.write_text('version: 100\n')
        self.assertNotEqual(self.invoke('plan').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_target_environment_mismatch_never_executes_terraform(self):
        self.env['TARGET_ENVIRONMENT'] = 'staging'
        result = self.invoke('plan')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must match TARGET_ENVIRONMENT', result.stderr)
        self.assertFalse(self.log.exists())

    def test_workspace_mismatch_never_executes_terraform(self):
        self.env['TARGET_WORKSPACE'] = 'sandbox'
        result = self.invoke('plan')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must match TARGET_WORKSPACE', result.stderr)
        self.assertFalse(self.log.exists())

    def test_another_workspaces_plan_cannot_be_applied(self):
        self.assertEqual(self.invoke('plan').returncode, 0)
        self.config['workspace']['name'] = 'sandbox'
        self.yaml.write_text(yaml.safe_dump(self.config))
        before = self.log.read_text()
        result = self.invoke('apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('create and review a new plan', result.stderr)
        self.assertEqual(self.log.read_text(), before)

    def test_cross_workspace_state_keys_are_rejected(self):
        command = [sys.executable, str(TOOLS / 'terraform_environment.py'), 'plan', str(self.yaml),
                   '--root', '01-infra', '--state-bucket', 'state', '--state-region', 'eu-west-1',
                   '--infra-state-key', 'databricks/dev/sandbox/01-infra.tfstate',
                   '--account-state-key', 'databricks/dev/sandbox/02-account.tfstate', '--artifacts', str(self.artifacts)]
        result = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('namespace', result.stderr)
        self.assertFalse(self.log.exists())

    def test_runner_supports_staging_and_rejects_production_before_terraform(self):
        self.config['environment']['name'] = 'staging'
        self.yaml.write_text(yaml.safe_dump(self.config))
        result = self.invoke('plan')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.log.exists())

        self.log.unlink()
        self.config['environment']['name'] = 'production'
        self.yaml.write_text(yaml.safe_dump(self.config))
        result = self.invoke('plan')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('supports only dev and staging', result.stderr)
        self.assertFalse(self.log.exists())

    def test_supplemental_input_cannot_override_yaml(self):
        from unittest.mock import patch
        folder = self.base / 'platform/terraform-inputs/dev'
        folder.mkdir(parents=True)
        path = folder / 'shared.01-infra.json'
        path.write_text(json.dumps({'aws_region': 'us-east-1'}))
        with patch.object(runner, 'FOUNDATION', self.base):
            with self.assertRaises(runner.ConfigError):
                runner.inputs(self.config, '01-infra', 'state', 'eu-west-1', 'existing/dev/infra.tfstate')
            path.write_text(json.dumps({'enable_observability_bucket': True}))
            values = runner.inputs(self.config, '01-infra', 'state', 'eu-west-1', 'existing/dev/infra.tfstate')
            self.assertTrue(values['enable_observability_bucket'])
            self.assertEqual(values['aws_region'], 'eu-west-1')

    def test_changed_upstream_state_requires_new_account_plan(self):
        result = self.invoke('plan', '02-account')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.env['TEST_UPSTREAM_VERSION'] = 'v2'
        result = self.invoke('apply', '02-account')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('create and review a new plan', result.stderr)


if __name__ == '__main__':
    unittest.main()
