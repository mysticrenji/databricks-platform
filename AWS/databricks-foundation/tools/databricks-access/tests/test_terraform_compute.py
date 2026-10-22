"""Credential-free persona compute rendering, ownership and execution checks."""
import copy
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configuration import ConfigError, FOUNDATION
import terraform_compute as runner
from test_terraform_entitlements import account_state


class ComputeTests(unittest.TestCase):
    def setUp(self):
        self.bundle = runner.load_compute()
        self.intent = runner.render(self.bundle)
        self.feature_intent = runner.features.render(self.bundle)
        self.account = account_state(self.feature_intent)
        self.bound = runner.features.bind_values(self.bundle, self.feature_intent, self.account)
        self.values = runner.bind_values(self.bundle, self.intent, self.account)

    def feature_state(self):
        return {'outputs': {'target_identity': {'value': runner.features.target_identity(self.bound)},
                            'group_ids': {'value': {key: group['group_id'] for key, group in self.bound['groups'].items()}}},
                'resources': [{'mode': 'managed', 'type': 'databricks_entitlements', 'name': 'this',
                               'instances': [{'index_key': key, 'attributes': group}]}
                              for key, group in self.bound['groups'].items()]}

    def own_state(self):
        return {'outputs': {'target_identity': {'value': self.values['compute_identity']},
                            'compute_group_ids': {'value': self.values['compute_group_ids']}},
                'resources': [{'mode': 'managed', 'module': 'module.cluster_policies',
                               'type': 'databricks_cluster_policy', 'name': 'this',
                               'instances': [{'index_key': 'engineering-standard',
                                              'attributes': {'id': 'policy-123', 'name': 'engineering-standard'}}]}]}

    def args(self, directory, action):
        return SimpleNamespace(action=action, environment='dev', workspace='demo', state_bucket='state',
                               state_region='eu-central-1', confirm_environment='dev/demo', artifacts=Path(directory))

    def test_render_exact_persona_acls_and_warehouse_limits(self):
        self.assertEqual(set(self.intent), {'cluster_policies', 'warehouses', 'read_data_access_state'})
        self.assertFalse(self.intent['read_data_access_state'])
        self.assertEqual(self.intent['cluster_policies']['engineering-standard']['permissions'],
                         {'groups': {'dev-demo-engineers': 'CAN_USE'}})
        self.assertEqual(self.intent['cluster_policies']['ml-standard']['permissions'],
                         {'groups': {'dev-demo-ml': 'CAN_USE'}})
        warehouse = self.intent['warehouses']['analytics']
        self.assertEqual(warehouse['permissions']['groups'], {
            'dev-demo-admins': 'CAN_MANAGE', 'dev-demo-engineers': 'CAN_USE',
            'dev-demo-analysts': 'CAN_USE', 'dev-demo-ml': 'CAN_USE'})
        self.assertEqual((warehouse['cluster_size'], warehouse['auto_stop_mins'],
                          warehouse['min_num_clusters'], warehouse['max_num_clusters']), ('Small', 15, 1, 1))
        self.assertFalse(warehouse['enable_serverless_compute'])
        self.assertNotIn('groups', self.intent)
        self.assertNotIn('jobs', self.intent)
        self.assertNotIn('compute_identity', self.intent)

    def test_loader_needs_no_dataset_metastore_or_workload_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            foundation = Path(temporary)
            for relative in ('platform/compute/dev.yaml', 'platform/access/roles.yaml',
                             'platform/access/principals/dev/demo.yaml', 'platform/environments/dev/demo.yaml',
                             'platform/terraform-inputs/dev/demo.02-account.json'):
                destination = foundation / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(FOUNDATION / relative, destination)
            self.assertEqual(runner.render(runner.load_compute(foundation)), self.intent)
        with self.assertRaises(ConfigError):
            runner.load_compute(environment='staging')

    def test_ownership_rejects_unbound_root_unknown_resources_and_competing_acl(self):
        own = self.own_state()
        runner.check_ownership(self.values, {runner.ROOT: own})
        bad = copy.deepcopy(own)
        bad['outputs']['target_identity']['value'] = {}
        with self.assertRaisesRegex(ConfigError, 'binding'):
            runner.check_ownership(self.values, {runner.ROOT: bad})
        bad = copy.deepcopy(own)
        bad['resources'][0]['type'] = 'databricks_cluster'
        with self.assertRaisesRegex(ConfigError, 'outside YAML'):
            runner.check_ownership(self.values, {runner.ROOT: bad})
        foreign = {'resources': [{'mode': 'managed', 'type': 'databricks_permissions', 'name': 'legacy',
                                  'instances': [{'attributes': {'cluster_policy_id': 'policy-123'}}]}]}
        with self.assertRaisesRegex(ConfigError, 'ACL migration'):
            runner.check_ownership(self.values, {runner.ROOT: own, '05-permissions': foreign})
        with self.assertRaisesRegex(ConfigError, 'already owned'):
            runner.check_ownership(self.values, {runner.ROOT: None, '03-data-access': own})

    def test_entitlements_must_be_applied_with_current_binding_and_flags(self):
        state = self.feature_state()
        states = {'02-workspace-access': state, '02-account': self.account, runner.ROOT: None}
        runner.check_features(self.bundle, self.account, states)
        state['resources'][1]['instances'][0]['attributes'] = {
            **state['resources'][1]['instances'][0]['attributes'], 'allow_cluster_create': True}
        with self.assertRaisesRegex(ConfigError, 'differs from persona'):
            runner.check_features(self.bundle, self.account, states)
        with self.assertRaisesRegex(ConfigError, 'before compute'):
            runner.check_features(self.bundle, self.account, {**states, '02-workspace-access': None})

    def test_plan_restricts_addresses_and_actions(self):
        def plan(address, actions):
            return {'resource_changes': [{'mode': 'managed', 'address': address, 'change': {'actions': actions}}]}
        address = 'module.cluster_policies.databricks_cluster_policy.this["engineering-standard"]'
        runner.check_plan(plan(address, ['create']), self.intent)
        runner.check_plan(plan(address, ['delete']), self.intent, retirement=True)
        for retirement, actions in ((False, ['delete']), (False, ['delete', 'create']), (True, ['create'])):
            with self.subTest(actions=actions), self.assertRaises(ConfigError):
                runner.check_plan(plan(address, actions), self.intent, retirement)
        with self.assertRaisesRegex(ConfigError, 'forbidden resource'):
            runner.check_plan(plan('databricks_cluster.running', ['create']), self.intent)

    def test_read_only_preflight_checks_availability_and_refuses_name_adoption(self):
        workspace = SimpleNamespace(
            clusters=SimpleNamespace(
                spark_versions=Mock(return_value=SimpleNamespace(versions=[
                    SimpleNamespace(key='16.4.x-scala2.12'), SimpleNamespace(key='16.4.x-cpu-ml-scala2.12')])),
                list_node_types=Mock(return_value=SimpleNamespace(node_types=[SimpleNamespace(node_type_id=name)
                    for name in ('m5d.large', 'm5d.xlarge', 'r5d.large', 'r5d.xlarge')]))),
            cluster_policies=SimpleNamespace(list=Mock(return_value=[])),
            warehouses=SimpleNamespace(list=Mock(return_value=[])))
        states = {runner.ROOT: self.own_state(), '02-account': self.account}
        with patch.dict(sys.modules, {'databricks.sdk': SimpleNamespace(WorkspaceClient=lambda **kwargs: workspace)}), \
             patch.dict(os.environ, {'DATABRICKS_CLIENT_ID': 'test', 'DATABRICKS_CLIENT_SECRET': 'test'}), \
             patch.object(runner.features, 'preflight'):
            runner.preflight(self.bundle, self.intent, self.values, states)
            workspace.cluster_policies.list.return_value = [SimpleNamespace(name='engineering-standard', policy_id='foreign')]
            with self.assertRaisesRegex(ConfigError, 'reviewed import'):
                runner.preflight(self.bundle, self.intent, self.values, states)
            workspace.cluster_policies.list.return_value = [SimpleNamespace(name='engineering-standard', policy_id='policy-123')]
            runner.preflight(self.bundle, self.intent, self.values, states)
            workspace.clusters.spark_versions.return_value = SimpleNamespace(versions=[])
            with self.assertRaisesRegex(ConfigError, 'runtimes are unavailable'):
                runner.preflight(self.bundle, self.intent, self.values, states)
            # Retirement must work even if an old approved runtime was removed.
            runner.preflight(self.bundle, self.intent, self.values, states, retirement=True)

    def test_warehouse_name_adoption_is_also_rejected(self):
        workspace = SimpleNamespace(cluster_policies=SimpleNamespace(list=lambda: []),
                                    warehouses=SimpleNamespace(list=lambda: [SimpleNamespace(name='analytics', id='foreign')]))
        with patch.dict(sys.modules, {'databricks.sdk': SimpleNamespace(WorkspaceClient=lambda **kwargs: workspace)}), \
             patch.dict(os.environ, {'DATABRICKS_CLIENT_ID': 'test', 'DATABRICKS_CLIENT_SECRET': 'test'}), \
             patch.object(runner.features, 'preflight'):
            with self.assertRaisesRegex(ConfigError, 'reviewed import'):
                runner.preflight(self.bundle, self.intent, self.values,
                                 {runner.ROOT: None, '02-account': self.account}, retirement=True)

    def test_manual_main_and_admin_gates_precede_state_and_terraform(self):
        for action in ('plan', 'apply', 'preview-destroy', 'destroy'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as temporary, \
                 patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/branch', 'GITHUB_EVENT_NAME': 'workflow_dispatch'}), \
                 patch.object(runner, 'read_state') as state:
                with self.assertRaisesRegex(ConfigError, 'manual dispatch on main'):
                    runner.execute(self.args(temporary, action))
                state.assert_not_called()
        for action in ('apply', 'destroy'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as temporary, \
                 patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch'}), \
                 patch.object(runner.provision, 'require_demo_apply', side_effect=ConfigError('blocked')) as gate, \
                 patch.object(runner, 'read_state') as state:
                with self.assertRaisesRegex(ConfigError, 'blocked'):
                    runner.execute(self.args(temporary, action))
                gate.assert_called_once_with('dev/demo', destroy=action == 'destroy')
                state.assert_not_called()

    def test_plan_apply_and_retirement_bind_exact_saved_plan_and_current_states(self):
        for first, second, actions in (('plan', 'apply', ['update']), ('preview-destroy', 'destroy', ['delete'])):
            with self.subTest(action=first), tempfile.TemporaryDirectory() as temporary:
                states = {'02-account.tfstate': self.account, '02-workspace-access.tfstate': self.feature_state(),
                          '04-workspace.tfstate': self.own_state()}
                calls = []
                def run(command, root):
                    calls.append(command)
                    if command[:2] == ['terraform', 'plan']:
                        Path(next(item[5:] for item in command if item.startswith('-out='))).write_bytes(b'exact-compute-plan')
                document = {'resource_changes': [{'mode': 'managed',
                    'address': 'module.cluster_policies.databricks_cluster_policy.this["engineering-standard"]',
                    'change': {'actions': actions}}]}
                with patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch'}), \
                     patch.object(runner, 'read_state', side_effect=lambda bucket, key, region, folder: states.get(key.rsplit('/', 1)[1])), \
                     patch.object(runner.provision, 'check_identity'), patch.object(runner.provision, 'capture', return_value='commit'), \
                     patch.object(runner.provision, 'require_demo_apply'), patch.object(runner.provision, 'run', side_effect=run), \
                     patch.object(runner.shutil, 'copytree'), patch.object(runner, 'preflight'), \
                     patch.object(runner.subprocess, 'check_output', return_value=json.dumps(document)):
                    runner.execute(self.args(temporary, first))
                    runner.execute(self.args(temporary, second))
                    states['01-infra.tfstate'] = {'version': 4, 'serial': 99, 'resources': []}
                    before = list(calls)
                    with self.assertRaisesRegex(ConfigError, 'changed'):
                        runner.execute(self.args(temporary, second))
                    self.assertEqual(calls, before)
                plans = [call for call in calls if call[:2] == ['terraform', 'plan']]
                applies = [call for call in calls if call[:2] == ['terraform', 'apply']]
                self.assertEqual(len(plans), 1)
                self.assertEqual(len(applies), 1)
                self.assertEqual(applies[0][-1], str(Path(temporary) / 'terraform.tfplan'))
                self.assertEqual('-destroy' in plans[0], first == 'preview-destroy')
                self.assertNotIn('-auto-approve', applies[0])

    def test_empty_retirement_needs_no_upstream_sdk_or_terraform(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch'}), \
             patch.object(runner, 'read_state', return_value=None), patch.object(runner.provision, 'check_identity'), \
             patch.object(runner.provision, 'capture', return_value='commit'), \
             patch.object(runner.provision, 'require_demo_apply') as gate, \
             patch.object(runner.provision, 'run') as terraform, patch.object(runner, 'preflight') as sdk:
            runner.execute(self.args(temporary, 'preview-destroy'))
            runner.execute(self.args(temporary, 'destroy'))
            gate.assert_called_once_with('dev/demo', destroy=True)
            sdk.assert_not_called()
            terraform.assert_not_called()


if __name__ == '__main__':
    unittest.main()
