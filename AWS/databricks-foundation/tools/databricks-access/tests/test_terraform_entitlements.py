"""Credential-free regression checks for the isolated workspace feature layer."""
import copy
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configuration import ConfigError, load_workspace_access
import terraform_entitlements as runner


def resource(kind, attributes):
    return {'mode': 'managed', 'type': kind, 'name': 'this', 'instances': [{'attributes': attributes, **({'index_key': 'admins'} if kind == 'databricks_entitlements' else {})}]}


def account_state(intent):
    state = {'version': 4, 'resources': [], 'outputs': {
        'workspace_id': {'value': 123},
        'workspace_url': {'value': 'https://dev-demo.cloud.databricks.com'},
        'account_group_ids': {'value': {}}}}
    for index, group in enumerate(intent['groups'].values(), 100):
        group_id = str(index)
        state['outputs']['account_group_ids']['value'][group['display_name']] = group_id
        state['resources'].extend([
            resource('databricks_group', {'id': group_id, 'display_name': group['display_name']}),
            resource('databricks_mws_permission_assignment', {'workspace_id': 123,
                     'principal_id': group_id, 'permissions': [group['workspace_role']]})])
    return state


class WorkspaceFeaturesTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/main'})
        environment.start()
        self.addCleanup(environment.stop)
        self.bundle = load_workspace_access()
        self.intent = runner.render(self.bundle)
        self.account = account_state(self.intent)
        self.values = runner.bind_values(self.bundle, self.intent, self.account)

    def test_exact_matrix_without_ids_or_dataset_dependencies(self):
        expected = {'admins': (True, True, True, True), 'engineers': (True, True, False, False),
                    'analysts': (False, True, False, False), 'ml': (True, True, False, False)}
        self.assertEqual(set(self.intent['groups']), set(expected))
        for key, flags in expected.items():
            group = self.intent['groups'][key]
            self.assertEqual(tuple(group['entitlements'][field] for field in runner.ENTITLEMENTS), flags)
            self.assertNotIn('group_id', group)
            self.assertEqual(group['workspace_role'], 'ADMIN' if key == 'admins' else 'USER')
        # Dataset files and target registration are deliberately outside this loader.
        with tempfile.TemporaryDirectory() as temporary:
            foundation = Path(temporary)
            for relative in ('platform/access/roles.yaml', 'platform/access/principals/dev/demo.yaml',
                             'platform/terraform-inputs/dev/demo.02-account.json', 'platform/environments/dev/demo.yaml'):
                source = runner.FOUNDATION / relative
                destination = foundation / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(source.read_bytes())
            (foundation / 'platform/access/targets/dev').mkdir(parents=True)
            (foundation / 'platform/access/targets/dev/demo.yaml').write_text('invalid: [')
            self.assertEqual(runner.render(load_workspace_access(foundation)), self.intent)

    def test_invalid_group_id_role_or_url_is_blocked(self):
        for mutation in ('id', 'role', 'url'):
            with self.subTest(mutation=mutation):
                state = copy.deepcopy(self.account)
                if mutation == 'id':
                    state['outputs']['account_group_ids']['value']['dev-demo-admins'] = '999'
                elif mutation == 'role':
                    state['resources'][1]['instances'][0]['attributes']['permissions'] = ['USER']
                else:
                    state['outputs']['workspace_url']['value'] = 'http://wrong.example'
                with self.assertRaises(ConfigError):
                    runner.bind_values(self.bundle, self.intent, state)

    def test_ownership_rejects_other_roots_and_changed_binding(self):
        own = {'resources': [resource('databricks_entitlements', {'group_id': '100'})],
               'outputs': {'target_identity': {'value': runner.target_identity(self.values)},
                           'group_ids': {'value': {key: group['group_id'] for key, group in self.values['groups'].items()}}}}
        runner.check_ownership(self.values, {'02-account': self.account, runner.ROOT: own})
        for root in ('04-workspace', '05-permissions'):
            with self.assertRaisesRegex(ConfigError, 'already owned'):
                runner.check_ownership(self.values, {root: {'resources': [resource('databricks_entitlements', {'group_id': '100'})]}})
        own['outputs']['group_ids']['value']['admins'] = '999'
        with self.assertRaisesRegex(ConfigError, 'IDs changed'):
            runner.check_ownership(self.values, {runner.ROOT: own})
        own['outputs']['group_ids']['value']['admins'] = '100'
        own['outputs']['target_identity']['value']['workspace_id'] = '999'
        with self.assertRaisesRegex(ConfigError, 'different or unknown'):
            runner.check_ownership(self.values, {runner.ROOT: own})

    def test_inline_entitlements_are_duplicate_ownership(self):
        state = copy.deepcopy(self.account)
        state['resources'][0]['instances'][0]['attributes']['workspace_access'] = True
        with self.assertRaisesRegex(ConfigError, 'Inline group entitlements'):
            runner.check_ownership(self.values, {'02-account': state})

    def test_restrict_plan_types_and_actions(self):
        def plan(kind, actions):
            return {'resource_changes': [{'mode': 'managed', 'type': kind, 'change': {'actions': actions}}]}
        for actions in (['create'], ['update'], ['no-op']):
            runner.check_plan(plan('databricks_entitlements', actions))
        for actions in (['delete'], ['no-op']):
            runner.check_plan(plan('databricks_entitlements', actions), True)
        for retirement, actions in ((False, ['delete']), (False, ['delete', 'create']), (True, ['update']), (True, ['create'])):
            with self.assertRaises(ConfigError):
                runner.check_plan(plan('databricks_entitlements', actions), retirement)
        for kind in ('databricks_group', 'databricks_grant', 'databricks_mws_permission_assignment'):
            with self.assertRaises(ConfigError):
                runner.check_plan(plan(kind, ['create']))

    def test_bound_manifest_expires_and_rejects_operation_or_plan_drift(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'manifest.json'
            binding = {'operation': 'workspace-entitlements', 'states': {'02-account': 'hash'}}
            runner.save_manifest(path, binding, b'plan')
            saved = json.loads(path.read_text())
            runner.check_saved_plan(saved, binding, b'plan')
            with self.assertRaises(ConfigError):
                runner.check_saved_plan(saved, {**binding, 'operation': 'retire-entitlements'}, b'plan')
            with self.assertRaises(ConfigError):
                runner.check_saved_plan(saved, binding, b'changed')
            with self.assertRaisesRegex(ConfigError, 'expired'):
                runner.check_saved_plan(saved, binding, b'plan', datetime.now(timezone.utc) + timedelta(hours=25))

    def args(self, temporary, action):
        return SimpleNamespace(action=action, artifacts=Path(temporary), environment='dev', workspace='demo',
                               state_bucket='state', state_region='eu-west-1', confirm_environment='dev/demo')

    def test_empty_retirement_is_bound_and_never_calls_sdk_or_terraform(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(runner, 'read_state', return_value=None), \
             patch.object(runner.provision, 'check_identity'), patch.object(runner.provision, 'capture', return_value='commit'), \
             patch.object(runner.provision, 'run') as run, patch.object(runner, 'preflight') as sdk, \
             patch.object(runner.provision, 'require_demo_apply') as gate:
            runner.execute(self.args(temporary, 'preview-destroy'))
            runner.execute(self.args(temporary, 'destroy'))
            gate.assert_called_once_with('dev/demo', destroy=True)
            sdk.assert_not_called()
            run.assert_not_called()
            with self.assertRaises(ConfigError):
                runner.execute(self.args(temporary, 'preview-destroy'))

    def test_missing_confirmation_or_unreadable_state_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = self.args(temporary, 'destroy')
            args.confirm_environment = 'dev/other'
            with self.assertRaisesRegex(ConfigError, 'confirm-environment'):
                runner.execute(args)
            with patch.object(runner.provision, 'check_identity'), \
                 patch.object(runner, 'read_state', side_effect=runner.EnvironmentConfigError('denied')):
                with self.assertRaisesRegex(runner.EnvironmentConfigError, 'denied'):
                    runner.execute(self.args(temporary, 'preview-destroy'))

    def test_compute_must_be_retired_before_entitlement_execution(self):
        compute = {'resources': [resource('databricks_cluster_policy', {'id': 'policy'})]}
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(runner, 'read_state', side_effect=lambda bucket, key, region, folder:
                          compute if key.endswith('/04-workspace.tfstate') else None), \
             patch.object(runner.provision, 'check_identity'), \
             patch.object(runner.provision, 'require_demo_apply'), patch.object(runner, 'preflight') as sdk:
            with self.assertRaisesRegex(ConfigError, 'Retire root04 compute'):
                runner.execute(self.args(temporary, 'destroy'))
            sdk.assert_not_called()

    def test_plan_apply_and_retirement_use_exact_saved_plan(self):
        own = {'resources': [resource('databricks_entitlements', {'group_id': '100'})],
               'outputs': {'target_identity': {'value': runner.target_identity(self.values)},
                           'group_ids': {'value': {key: group['group_id'] for key, group in self.values['groups'].items()}}}}
        for preview_action, apply_action, actions in (('plan', 'apply', ['update']),
                                                      ('preview-destroy', 'destroy', ['delete'])):
            with self.subTest(action=preview_action), tempfile.TemporaryDirectory() as temporary:
                def state_reader(bucket, key, region, folder):
                    if key.endswith('/02-account.tfstate'):
                        return self.account
                    if key.endswith(f'/{runner.ROOT}.tfstate'):
                        return own
                    return None

                calls = []
                def terraform_run(command, root):
                    calls.append(command)
                    if command[:2] == ['terraform', 'plan']:
                        Path(next(item[5:] for item in command if item.startswith('-out='))).write_bytes(b'reviewed-plan')

                document = {'resource_changes': [{'mode': 'managed', 'type': 'databricks_entitlements',
                                                 'change': {'actions': actions}}]}
                with patch.object(runner, 'read_state', side_effect=state_reader), \
                     patch.object(runner.provision, 'check_identity'), \
                     patch.object(runner.provision, 'capture', return_value='commit'), \
                     patch.object(runner.provision, 'run', side_effect=terraform_run), \
                     patch.object(runner, 'preflight'), \
                     patch.object(runner.provision, 'require_demo_apply'), \
                     patch.object(runner.shutil, 'copytree'), \
                     patch.object(runner.subprocess, 'check_output', return_value=json.dumps(document)):
                    runner.execute(self.args(temporary, preview_action))
                    runner.execute(self.args(temporary, apply_action))
                plans = [call for call in calls if call[:2] == ['terraform', 'plan']]
                applies = [call for call in calls if call[:2] == ['terraform', 'apply']]
                self.assertEqual(len(plans), 1)
                self.assertEqual(len(applies), 1)
                self.assertEqual('-destroy' in plans[0], preview_action == 'preview-destroy')
                self.assertEqual(applies[0][-1], str(Path(temporary) / 'terraform.tfplan'))
                self.assertNotIn('-auto-approve', applies[0])
                self.assertFalse(any(call[:2] == ['terraform', 'destroy'] for call in calls))

    def test_nonmain_live_actions_fail_before_state_or_sdk_access(self):
        for action in ('plan', 'apply', 'preview-destroy', 'destroy'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as temporary, \
                 patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/feature'}), \
                 patch.object(runner, 'read_state') as state, patch.object(runner, 'preflight') as sdk:
                with self.assertRaisesRegex(ConfigError, 'only on main'):
                    runner.execute(self.args(temporary, action))
                state.assert_not_called()
                sdk.assert_not_called()

    def test_apply_and_retirement_use_their_respective_gates(self):
        for action in ('apply', 'destroy'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as temporary, \
                 patch.object(runner.provision, 'require_demo_apply', side_effect=ConfigError('gate blocked')) as demo, \
                 patch.object(runner, 'read_state') as state:
                with self.assertRaisesRegex(ConfigError, 'gate blocked'):
                    runner.execute(self.args(temporary, action))
                state.assert_not_called()
                if action == 'apply':
                    demo.assert_called_once_with('dev/demo')
                else:
                    demo.assert_called_once_with('dev/demo', destroy=True)

    def test_approval_preflight_checks_demo_policy_without_state_sdk_or_terraform(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(runner.provision, 'require_demo_apply') as gate, \
             patch.object(runner, 'read_state') as state, patch.object(runner, 'preflight') as sdk, \
             patch.object(runner.provision, 'run') as terraform:
            runner.execute(self.args(temporary, 'check-approval'))
            gate.assert_called_once_with('dev/demo')
            state.assert_not_called()
            sdk.assert_not_called()
            terraform.assert_not_called()


if __name__ == '__main__':
    unittest.main()
