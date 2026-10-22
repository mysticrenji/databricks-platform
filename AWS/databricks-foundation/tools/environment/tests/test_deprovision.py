"""Exercise retention and destructive gates without contacting AWS or Terraform."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
import subprocess
import sys
from unittest.mock import patch

import test_environment
import deprovision_environment as destroy
from test_storage_cleanup import FakeS3
from environment import ConfigError


def resource(kind, name, module=None, index=None):
    result = {'mode': 'managed', 'type': kind, 'name': name,
              'instances': [{'attributes': {'id': 'example'}}]}
    if module:
        result['module'] = module
    if index is not None:
        result['instances'][0]['index_key'] = index
    return result


class DeprovisionTests(unittest.TestCase):
    def setUp(self):
        fixture = test_environment.EnvironmentTests()
        fixture.setUp()
        self.config = fixture.config
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.yaml = self.base / 'dev.yaml'
        self.yaml.write_text('test yaml')
        self.args = SimpleNamespace(action='preview', config=self.yaml, root='01-infra',
                                    state_bucket='state', state_region='eu-central-1',
                                    infra_state_key='databricks/dev/shared/01-infra.tfstate', account_state_key='databricks/dev/shared/02-account.tfstate',
                                    data_access_state_key='databricks/dev/shared/03-data-access.tfstate', workspace_state_key='databricks/dev/shared/04-workspace.tfstate',
                                    artifacts=self.base / 'artifacts', confirm_environment='dev/shared')
        self.states = {
            'infra': {'version': 4, 'serial': 1, 'resources': [
                resource('aws_vpc', 'this', 'module.vpc'),
                resource('aws_s3_bucket', 'this', 'module.root_storage'),
                resource('aws_s3_bucket_policy', 'this', 'module.root_storage'),
                resource('aws_kms_key', 'this', 'module.kms', 0),
            ]},
            'account': None, 'data': None, 'workspace': None, 'permissions': None, 'features': None,
        }
        self.changes = [{'address': 'module.vpc.aws_vpc.this', 'mode': 'managed',
                         'type': 'aws_vpc', 'change': {'actions': ['delete'], 'before': {'id': 'example'}, 'after': None}}]
        self.calls = []
        self.backends = []

        def copytree(source, destination, **kwargs):
            destination.mkdir(parents=True, exist_ok=True)
            if str(destination).endswith('environments/dev'):
                root = destination / self.args.root
                root.mkdir()
                (root / 'providers.tf').write_text('terraform { backend "s3" {} }')

        def run(command, cwd):
            self.calls.append(command)
            self.backends.append((cwd / 'providers.tf').read_text())

        patches = [
            patch.object(destroy, 'load', return_value=self.config),
            patch.object(destroy, 'read_state', side_effect=lambda bucket, key, region, folder: copy.deepcopy(self.states[{'01-infra.tfstate': 'infra', '02-account.tfstate': 'account', '03-data-access.tfstate': 'data', '04-workspace.tfstate': 'workspace', '05-permissions.tfstate': 'permissions', '02-workspace-access.tfstate': 'features'}[key.split('/')[-1]]])),
            patch.object(destroy, 'plan_changes', side_effect=lambda *args: copy.deepcopy(self.changes)),
            patch.object(destroy.provision, 'check_identity'),
            patch.object(destroy.provision, 'manifest', side_effect=lambda config, root, values, backend: {'config': copy.deepcopy(config), 'root': root, 'backend': backend, 'inputs': values}),
            patch.object(destroy.provision, 'run', side_effect=run),
            patch.object(destroy.shutil, 'copytree', side_effect=copytree),
            patch.dict('os.environ', {'TARGET_ENVIRONMENT': 'dev', 'ENVIRONMENT_YAML_DESTROY_ENABLED': 'true'}, clear=True),
        ]
        for item in patches:
            item.start()
            self.addCleanup(item.stop)

    def test_preview_retains_storage_only_in_local_state_copy(self):
        original = copy.deepcopy(self.states)
        destroy.execute(self.args)
        self.assertEqual(self.states, original)
        self.assertTrue(all('backend "local"' in backend for backend in self.backends))
        self.assertFalse(any(command[1] == 'destroy' for command in self.calls))
        remove = next(command for command in self.calls if command[1:3] == ['state', 'rm'])
        self.assertIn('module.root_storage.aws_s3_bucket.this', remove)
        self.assertIn('module.root_storage.aws_s3_bucket_policy.this', remove)
        self.assertIn('module.kms.aws_kms_key.this[0]', remove)
        self.assertNotIn('module.vpc.aws_vpc.this', remove)
        self.assertTrue((self.args.artifacts / '01-infra.before.tfstate').exists())
        plan = next(command for command in self.calls if command[1] == 'plan')
        self.assertIn('-destroy', plan)

    def test_execution_uses_original_backend_retains_then_calls_destroy(self):
        destroy.execute(self.args)
        self.calls.clear()
        self.backends.clear()
        self.args.action = 'destroy'
        destroy.execute(self.args)
        commands = [command[1] for command in self.calls]
        self.assertEqual(commands, ['init', 'validate', 'state', 'plan', 'destroy'])
        self.assertTrue(all('backend "s3"' in backend for backend in self.backends))
        self.assertIn('-auto-approve', self.calls[-1])
        self.assertFalse(any('-target' in arg for command in self.calls for arg in command))
        self.assertIn('-lock-timeout=60s', self.calls[-1])

    def test_destroy_requires_confirmation_and_separate_opt_in(self):
        self.args.action = 'destroy'
        self.args.confirm_environment = 'staging'
        with self.assertRaisesRegex(ConfigError, 'matching --confirm-environment'):
            destroy.execute(self.args)
        self.args.confirm_environment = 'dev/shared'
        with patch.dict('os.environ', {'ENVIRONMENT_YAML_DESTROY_ENABLED': 'false'}):
            with self.assertRaises(ConfigError):
                destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_demo_destroy_checks_admin_before_state_access_then_uses_reviewed_preview(self):
        self.config['workspace']['name'] = 'demo'
        for field in ('infra_state_key', 'account_state_key', 'data_access_state_key', 'workspace_state_key'):
            setattr(self.args, field, getattr(self.args, field).replace('/shared/', '/demo/'))
        self.args.confirm_environment = 'dev/demo'
        destroy.execute(self.args)
        self.calls.clear()
        self.args.action = 'destroy'
        with patch.object(destroy, 'read_state', side_effect=AssertionError('State read before demo authorization')) as state, \
             patch.object(destroy.provision, 'check_identity') as identity:
            with self.assertRaisesRegex(ConfigError, 'manual workflow_dispatch'):
                destroy.execute(self.args)
            state.assert_not_called()
            identity.assert_not_called()
        with patch.dict('os.environ', {'GITHUB_REF': 'refs/heads/main',
                                      'GITHUB_EVENT_NAME': 'workflow_dispatch',
                                      'GITHUB_REPOSITORY': 'owner/repo', 'GITHUB_ACTOR': 'owner', 'GH_TOKEN': 'test'}), \
             patch.object(destroy.provision, 'capture', return_value='{"permission": "admin"}'):
            destroy.execute(self.args)
        self.assertEqual([command[1] for command in self.calls], ['init', 'validate', 'state', 'plan', 'destroy'])

    def test_destroy_cannot_use_another_workspaces_keys_or_confirmation(self):
        self.args.action = 'destroy'
        self.args.confirm_environment = 'dev/sandbox'
        with self.assertRaisesRegex(ConfigError, 'matching --confirm-environment'):
            destroy.execute(self.args)
        self.args.action = 'preview'
        self.args.infra_state_key = 'databricks/dev/sandbox/01-infra.tfstate'
        with self.assertRaisesRegex(ConfigError, 'namespace'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_changed_state_or_inputs_reject_execution_before_mutations(self):
        destroy.execute(self.args)
        self.calls.clear()
        self.args.action = 'destroy'
        self.states['infra']['serial'] += 1
        with self.assertRaisesRegex(ConfigError, 'state changed'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])
        self.states['infra']['serial'] -= 1
        self.config['features']['observability'] = False
        with self.assertRaisesRegex(ConfigError, 'state changed'):
            destroy.execute(self.args)

    def test_missing_or_tampered_preview_and_backup_reject_execution(self):
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.calls.clear()
        (self.args.artifacts / '01-infra.before.tfstate').write_text('{}')
        with self.assertRaisesRegex(ConfigError, 'backup artifact changed'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])
        (self.args.artifacts / 'changes.json').write_text('[]')
        with self.assertRaisesRegex(ConfigError, 'preview artifact changed'):
            destroy.execute(self.args)

    def test_requires_empty_downstream_states_and_distinct_bindings(self):
        for name in ('data', 'workspace', 'permissions', 'features', 'account'):
            with self.subTest(state=name):
                self.states[name] = {'version': 4, 'resources': [resource('databricks_catalog', 'example')]}
                with self.assertRaises(ConfigError):
                    destroy.execute(self.args)
                self.states[name] = None
        self.args.workspace_state_key = self.args.infra_state_key
        with self.assertRaisesRegex(ConfigError, 'distinct'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_permissions_state_blocks_both_roots_before_terraform(self):
        self.states['permissions'] = {'version': 4, 'resources': [resource('databricks_grant', 'existing_schema')]}
        for root in ('01-infra', '02-account'):
            with self.subTest(root=root):
                self.args.root = root
                with self.assertRaisesRegex(ConfigError, '05-permissions still manages resources'):
                    destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_workspace_features_must_be_retired_before_groups_or_infrastructure(self):
        self.states['features'] = {'version': 4, 'resources': [resource('databricks_entitlements', 'this')]}
        for root in ('01-infra', '02-account'):
            self.args.root = root
            with self.assertRaisesRegex(ConfigError, '02-workspace-access still manages resources'):
                destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_unreadable_feature_state_blocks_teardown(self):
        original = destroy.read_state

        def read_state(bucket, key, region, folder):
            if key.endswith('/02-workspace-access.tfstate'):
                raise ConfigError('Cannot read feature state: AccessDenied')
            return original(bucket, key, region, folder)

        with patch.object(destroy, 'read_state', side_effect=read_state):
            with self.assertRaisesRegex(ConfigError, 'feature state: AccessDenied'):
                destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_unreadable_permissions_state_blocks_before_terraform(self):
        original = destroy.read_state

        def read_state(bucket, key, region, folder):
            if key == 'databricks/dev/shared/05-permissions.tfstate':
                raise ConfigError(f'Cannot read state {key}: AccessDenied')
            return original(bucket, key, region, folder)

        with patch.object(destroy, 'read_state', side_effect=read_state):
            with self.assertRaisesRegex(ConfigError, '05-permissions.tfstate: AccessDenied'):
                destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_permissions_state_is_bound_and_backed_up_in_preview(self):
        self.states['permissions'] = {'version': 4, 'serial': 1, 'resources': []}
        destroy.execute(self.args)
        metadata = json.loads((self.args.artifacts / 'destroy-manifest.json').read_text())
        self.assertEqual(metadata['binding']['state_keys']['05-permissions'],
                         'databricks/dev/shared/05-permissions.tfstate')
        self.assertEqual(json.loads((self.args.artifacts / '05-permissions.before.tfstate').read_text()),
                         self.states['permissions'])
        self.args.action = 'destroy'
        self.calls.clear()
        self.states['permissions']['serial'] += 1
        with self.assertRaisesRegex(ConfigError, 'state changed'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_account_preview_allowed_with_infra_then_empty_root_is_noop(self):
        self.args.root = '02-account'
        self.states['account'] = {'version': 4, 'resources': [resource('databricks_mws_workspaces', 'this')]}
        self.changes = []
        destroy.execute(self.args)
        self.assertFalse(any(command[1:3] == ['state', 'rm'] for command in self.calls))
        self.calls.clear()
        self.states['account'] = {'version': 4, 'resources': []}
        destroy.execute(self.args)
        self.args.action = 'destroy'
        destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_plan_failure_stops_before_destroy(self):
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.calls.clear()
        with patch.object(destroy, 'plan_changes', side_effect=ConfigError('plan failed')):
            with self.assertRaises(ConfigError):
                destroy.execute(self.args)
        self.assertFalse(any(command[1] == 'destroy' for command in self.calls))

    def test_changed_preview_resource_actions_never_execute_destroy(self):
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.changes[0]['change']['before']['id'] = 'changed'
        self.calls.clear()
        with self.assertRaisesRegex(ConfigError, 'differ from approved preview'):
            destroy.execute(self.args)
        self.assertFalse(any(command[1] == 'destroy' for command in self.calls))

    def test_initialization_drift_stops_before_retention(self):
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.calls.clear()
        changed = copy.deepcopy(self.states['infra'])
        changed['serial'] += 1
        snapshots = [self.states['infra'], None, None, None, None, None, changed, None, None, None, None, None]
        with patch.object(destroy, 'read_state', side_effect=snapshots):
            with self.assertRaisesRegex(ConfigError, 'during initialization'):
                destroy.execute(self.args)
        self.assertFalse(any(command[1] in ('state', 'destroy') for command in self.calls))

    def test_production_and_terraform_overrides_are_rejected(self):
        self.config['environment']['name'] = 'production'
        with self.assertRaises(ConfigError):
            destroy.execute(self.args)
        self.config['environment']['name'] = 'dev'
        with patch.dict('os.environ', {'TF_CLI_ARGS_destroy': '-lock=false'}):
            with self.assertRaises(ConfigError):
                destroy.execute(self.args)
        self.assertEqual(self.calls, [])

    def test_plan_cannot_delete_storage_or_create_resources(self):
        for kind, actions in [('aws_s3_bucket', ['delete']), ('aws_kms_key', ['delete']), ('aws_vpc', ['create'])]:
            with self.subTest(kind=kind):
                with self.assertRaises(ConfigError):
                    destroy.require_destroy_only([{'type': kind, 'change': {'actions': actions}}])

    def enable_purge(self):
        self.args.purge_storage = True
        self.args.confirm_purge_storage = 'dev/shared'
        bucket = resource('aws_s3_bucket', 'root', 'module.root_storage')
        bucket['instances'][0]['attributes']['id'] = self.config['storage']['workspace_bucket_name']
        self.states['infra']['resources'][1] = bucket
        for scope in ('landing', 'uc_managed'):
            bucket = resource('aws_s3_bucket', 'this', 'module.data_storage', scope)
            bucket['instances'][0]['attributes']['id'] = f'databricks-dev-shared-{scope.replace("_", "-")}-123456789012'
            self.states['infra']['resources'].append(bucket)
        self.s3 = FakeS3()
        self.s3.region = self.config['environment']['aws_region']
        patcher = patch.object(destroy.storage_cleanup, 'client', return_value=self.s3)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_purge_preview_is_read_only_then_runs_only_after_verified_teardown(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])
        inventory = json.loads((self.args.artifacts / 'purge-storage.json').read_text())
        self.assertEqual(inventory[0]['versions'], 1001)
        self.args.action = 'destroy'
        original = destroy.provision.run

        def run(command, cwd):
            original(command, cwd)
            if command[1] == 'destroy':
                self.assertEqual(self.s3.writes, [])
                self.states['infra']['resources'] = []

        with patch.object(destroy.provision, 'run', side_effect=run):
            destroy.execute(self.args)
        self.assertFalse(self.s3.exists)

    def test_purge_requires_its_own_confirmation_and_is_bound_to_preview(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.args.confirm_purge_storage = ''
        with self.assertRaisesRegex(ConfigError, 'confirm-purge-storage'):
            destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])
        self.args.confirm_purge_storage = 'dev/shared'
        self.args.purge_storage = False
        with self.assertRaisesRegex(ConfigError, 'changed'):
            destroy.execute(self.args)

    def test_changed_storage_or_inventory_rejects_before_terraform_mutations(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.calls.clear()
        self.s3.versions.append({'Key': 'new-data', 'VersionId': 'new', 'Size': 2})
        with self.assertRaisesRegex(ConfigError, 'changed'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.s3.writes, [])

    def test_failed_or_incomplete_destroy_never_purges(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.args.action = 'destroy'
        with self.assertRaisesRegex(ConfigError, 'still manages resources'):
            destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])

    def test_terraform_destroy_failure_never_calls_storage_deletion(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.args.action = 'destroy'
        original = destroy.provision.run

        def run(command, cwd):
            if command[1] == 'destroy':
                raise subprocess.CalledProcessError(1, command)
            original(command, cwd)

        with patch.object(destroy.provision, 'run', side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):
                destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])

    def test_tampered_purge_inventory_stops_before_state_detachment(self):
        self.enable_purge()
        destroy.execute(self.args)
        self.args.action = 'destroy'
        self.calls.clear()
        (self.args.artifacts / 'purge-storage.json').write_text('[]')
        with self.assertRaisesRegex(ConfigError, 'inventory artifact changed'):
            destroy.execute(self.args)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.s3.writes, [])

    def test_account_root_accepts_purge_binding_but_never_deletes_storage(self):
        self.enable_purge()
        self.args.root = '02-account'
        self.states['account'] = {'version': 4, 'resources': [resource('databricks_mws_workspaces', 'this')]}
        self.changes = []
        destroy.execute(self.args)
        self.args.action = 'destroy'
        destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])

    def test_purge_refuses_to_guess_names_after_storage_was_detached(self):
        self.enable_purge()
        self.states['infra']['resources'] = [resource('aws_vpc', 'this')]
        with self.assertRaisesRegex(ConfigError, 'inventory'):
            destroy.execute(self.args)
        self.assertEqual(self.s3.writes, [])


class StateReadTests(unittest.TestCase):
    def test_only_missing_key_is_treated_as_absent(self):
        with tempfile.TemporaryDirectory() as folder:
            for message in ('(NoSuchKey)', '(404)'):
                with patch.object(destroy.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stderr=message)):
                    self.assertIsNone(destroy.read_state('bucket', 'key', 'eu-west-1', Path(folder)))
            with patch.object(destroy.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stderr='AccessDenied')):
                with self.assertRaises(ConfigError):
                    destroy.read_state('bucket', 'key', 'eu-west-1', Path(folder))


class WorkflowTests(unittest.TestCase):
    def test_destroy_order_and_concurrency_match_provisioning(self):
        import yaml
        workflows = test_environment.TOOLS.parents[3] / '.github/workflows'
        deprovision = yaml.load((workflows / 'environment-deprovision.yml').read_text(), Loader=yaml.BaseLoader)
        provision = yaml.load((workflows / 'environment-provision.yml').read_text(), Loader=yaml.BaseLoader)
        jobs = deprovision['jobs']
        self.assertEqual(jobs['account']['with']['root'], '02-account')
        self.assertEqual(jobs['infra']['needs'], 'account')
        self.assertEqual(jobs['infra']['with']['root'], '01-infra')
        self.assertIn('inputs.target_workspace', jobs['infra']['with']['target_workspace'])
        self.assertIn('inputs.execute_destroy', jobs['infra']['if'])
        self.assertIn("needs.account.result == 'success'", jobs['infra']['if'])
        self.assertEqual(deprovision['concurrency'], provision['concurrency'])
        self.assertEqual(list(deprovision['on']), ['workflow_dispatch'])
        self.assertEqual(deprovision['on']['workflow_dispatch']['inputs']['execute_destroy']['default'], 'false')

    def test_setup_helper_derives_workspace_keys_and_destroy_opt_in(self):
        import yaml
        fixture = test_environment.EnvironmentTests()
        fixture.setUp()
        helper = test_environment.TOOLS.parent / 'github-environment-setup/setup_github_environments.py'
        with tempfile.TemporaryDirectory(dir=test_environment.TOOLS) as folder:
            config = Path(folder) / 'config.yaml'
            config.write_text(yaml.safe_dump(fixture.config))
            command = [sys.executable, str(helper), 'dev', '--workspace', 'shared', '--repo', 'owner/repo', '--config', str(config),
                       '--state-bucket', 'state', '--databricks-client-id', 'client']
            result = subprocess.run(command + ['--infra-state-key', 'databricks/dev/other/01-infra.tfstate'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('namespace', result.stderr)
            result = subprocess.run(command + ['--enable-destroy'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('ENVIRONMENT_YAML_DESTROY_ENABLED --repo owner/repo --env dev-shared-apply --body true', result.stdout)
            self.assertNotIn('--env dev-shared-plan --body true', result.stdout)
            self.assertIn('TF_DATA_ACCESS_STATE_KEY', result.stdout)
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('ENVIRONMENT_YAML_DESTROY_ENABLED --repo owner/repo --env dev-shared-apply --body false', result.stdout)
            self.assertIn('databricks/dev/shared/03-data-access.tfstate', result.stdout)

    def test_setup_helper_cannot_select_another_workspace_config(self):
        import yaml
        fixture = test_environment.EnvironmentTests()
        fixture.setUp()
        helper = test_environment.TOOLS.parent / 'github-environment-setup/setup_github_environments.py'
        with tempfile.TemporaryDirectory(dir=test_environment.TOOLS) as folder:
            config = Path(folder) / 'config.yaml'
            config.write_text(yaml.safe_dump(fixture.config))
            command = [sys.executable, str(helper), 'dev', '--workspace', 'sandbox', '--repo', 'owner/repo',
                       '--config', str(config), '--state-bucket', 'state', '--databricks-client-id', 'client']
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('must declare workspace.name: sandbox', result.stderr)
            self.assertNotIn('Would run:', result.stdout)

    def test_setup_helper_default_finds_demo_in_platform_without_cloud_calls(self):
        helper = test_environment.TOOLS.parent / 'github-environment-setup/setup_github_environments.py'
        command = [sys.executable, str(helper), 'dev', '--workspace', 'demo',
                   '--repo', 'owner/repo', '--state-bucket', 'state', '--databricks-client-id', 'client']
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('AWS/databricks-foundation/platform/environments/dev/demo.yaml', result.stdout)
        self.assertIn('databricks/dev/demo/01-infra.tfstate', result.stdout)
        self.assertIn('databricks/dev/demo/04-workspace.tfstate', result.stdout)
        self.assertIn('ENVIRONMENT_YAML_APPLY_ENABLED --repo owner/repo --env dev-demo-apply --body false', result.stdout)
        self.assertNotIn('/config/environments/', result.stdout)


if __name__ == '__main__':
    unittest.main()
