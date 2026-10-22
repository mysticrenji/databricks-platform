import copy
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configuration import ConfigError, load_bundle
from terraform_permissions import (ROOT, bind_bootstrap_groups, check_ownership, check_plan, check_saved_plan,
                                   check_workspace_outputs, identity, preflight, render, require_apply_gate)


def state_resource(kind, **attributes):
    return {'version': 4, 'resources': [{'mode': 'managed', 'type': kind, 'instances': [{'attributes': attributes}]}]}


class RendererTests(unittest.TestCase):
    def test_renders_groups_and_grants_without_data_objects_or_compute(self):
        values = render(load_bundle())
        self.assertEqual(set(values), {'account_id', 'workspace_id', 'workspace_url', 'metastore_id', 'groups', 'grants'})
        self.assertEqual(len(values['groups']), 4)
        self.assertEqual(len(values['grants']), 9)
        self.assertEqual(values['groups']['admins']['workspace_role'], 'ADMIN')
        self.assertTrue(all(group['lifecycle'] == 'terraform' and not group.get('account_group_id')
                            for group in values['groups'].values()))
        self.assertNotIn('member_ids', values['groups']['engineers'])
        self.assertFalse(values['groups']['engineers']['entitlements']['allow_cluster_create'])
        table = next(grant for grant in values['grants'].values() if grant['object_type'] == 'table')
        self.assertEqual(table, {'object_type': 'table', 'object_name': 'dev_demo.gold.sales_summary',
                                 'group_key': 'engineers', 'privileges': ['SELECT']})

    def test_combines_requests_and_retains_shared_parent_usage(self):
        bundle = load_bundle()
        before = render(bundle)
        bundle['workloads'].append(copy.deepcopy(bundle['workloads'][0]))
        self.assertEqual(render(bundle), before)
        bundle['workloads'] = [request for request in bundle['workloads'] if request['persona'] != 'engineers']
        result = render(bundle)
        self.assertFalse(any(grant['group_key'] == 'engineers' for grant in result['grants'].values()))
        self.assertTrue(any(grant['object_type'] == 'catalog' and grant['group_key'] == 'analysts'
                            for grant in result['grants'].values()))

    def test_reordering_requests_does_not_change_resource_identity(self):
        bundle = load_bundle()
        before = render(bundle)
        bundle['workloads'].reverse()
        for request in bundle['workloads']:
            request['data_access'].reverse()
        self.assertEqual(render(bundle), before)


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.values = render(load_bundle())
        for group in self.values['groups'].values():
            group['lifecycle'] = 'create'

    def test_legacy_whole_acl_blocks_even_other_principal(self):
        with self.assertRaisesRegex(ConfigError, 'Whole-object ACL'):
            check_ownership(self.values, {'03-data-access': state_resource(
                'databricks_grants', schema='dev_demo.bronze', grant=[{'principal': 'unrelated'}])}, {})

    def test_legacy_single_principal_scope_can_coexist_without_overlap(self):
        state = state_resource('databricks_grant', schema='dev_demo.bronze', principal='unrelated')
        check_ownership(self.values, {'03-data-access': state}, {})
        state['resources'][0]['instances'][0]['attributes']['principal'] = 'dev-demo-engineers'
        with self.assertRaisesRegex(ConfigError, 'Principal/object'):
            check_ownership(self.values, {'03-data-access': state}, {})

    def test_group_conflicts_in_state_and_supplemental_are_rejected(self):
        with self.assertRaisesRegex(ConfigError, 'already owned'):
            check_ownership(self.values, {'02-account': state_resource('databricks_group', display_name='dev-demo-engineers')}, {})
        with self.assertRaisesRegex(ConfigError, 'overlap'):
            check_ownership(self.values, {}, {'account_groups': {'dev-demo-engineers': {}}})

    def test_existing_permissions_state_cannot_be_retargeted(self):
        state = state_resource('databricks_group', id='500', display_name='dev-demo-engineers')
        state['outputs'] = {'target_identity': {'value': identity(self.values)}}
        check_ownership(self.values, {ROOT: state}, {})
        state['outputs']['target_identity']['value']['metastore_id'] = 'other'
        with self.assertRaisesRegex(ConfigError, 'different or unknown target'):
            check_ownership(self.values, {ROOT: state}, {})

    def test_provisioning_output_binding_rejects_wrong_or_missing_state(self):
        outputs = {key: {'value': self.values[key]} for key in ('workspace_id', 'workspace_url')}
        check_workspace_outputs(self.values, {'outputs': outputs})
        for state in (None, {'outputs': outputs | {'workspace_id': {'value': 999}}},
                      {'outputs': outputs | {'workspace_url': {'value': 'https://other.cloud.databricks.com'}}}):
            with self.subTest(state=state), self.assertRaisesRegex(ConfigError, 'provisioning outputs'):
                check_workspace_outputs(self.values, state)

    def test_external_group_assignment_and_entitlement_owners_are_preserved(self):
        self.values['groups']['engineers'].update(lifecycle='external', account_group_id='777')
        assignment = state_resource('databricks_mws_permission_assignment',
                                    workspace_id=self.values['workspace_id'], principal_id=777)
        with self.assertRaisesRegex(ConfigError, 'assignment is already owned'):
            check_ownership(self.values, {'02-account': assignment}, {})
        entitlements = state_resource('databricks_entitlements', group_id='777')
        with self.assertRaisesRegex(ConfigError, 'entitlements are already owned'):
            check_ownership(self.values, {'04-workspace': entitlements}, {})
        assignment['resources'][0]['instances'][0]['attributes']['workspace_id'] = 123
        check_ownership(self.values, {'02-account': assignment}, {})


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.values = render(load_bundle())
        self.state = {'version': 4, 'resources': [], 'outputs': {'account_group_ids': {'value': {}}}}
        self.supplemental = {'account_groups': {}}
        for number, group in enumerate(self.values['groups'].values(), 700):
            group.update(lifecycle='terraform')
            group.pop('account_group_id', None)
            name = group['display_name']
            self.state['outputs']['account_group_ids']['value'][name] = str(number)
            self.state['resources'] += state_resource('databricks_group', id=str(number), display_name=name)['resources']
            self.state['resources'] += state_resource('databricks_mws_permission_assignment',
                workspace_id=self.values['workspace_id'], principal_id=number,
                permissions=[group['workspace_role']])['resources']
            self.supplemental['account_groups'][name] = {'workspace_permission': group['workspace_role'], 'member_ids': {}}

    def test_verified_root02_bootstrap_is_referenced_without_mutating_rendered_inputs(self):
        bound = bind_bootstrap_groups(self.values, self.state)
        self.assertNotIn('account_group_id', self.values['groups']['admins'])
        self.assertEqual(bound['groups']['admins']['account_group_id'], '700')
        check_ownership(bound, {'02-account': self.state}, self.supplemental)
        with self.assertRaisesRegex(ConfigError, 'bound before'):
            check_ownership(self.values, {'02-account': self.state}, self.supplemental)

    def test_missing_wrong_and_duplicate_group_outputs_are_rejected(self):
        for value in (None, '', 'wrong', 700, '999', '701'):
            state = copy.deepcopy(self.state)
            state['outputs']['account_group_ids']['value']['dev-demo-admins'] = value
            with self.subTest(value=value), self.assertRaises(ConfigError):
                bind_bootstrap_groups(self.values, state)
        with self.assertRaisesRegex(ConfigError, 'numeric'):
            bind_bootstrap_groups(self.values, None)
        self.values['groups']['admins']['account_group_id'] = '999'
        with self.assertRaisesRegex(ConfigError, 'reviewed reference'):
            bind_bootstrap_groups(self.values, self.state)

    def test_managed_name_id_and_workspace_role_must_match(self):
        for resource_index, field, value in ((0, 'id', '999'), (0, 'display_name', 'other'),
                                              (1, 'workspace_id', 999), (1, 'principal_id', 999),
                                              (1, 'permissions', ['USER'])):
            state = copy.deepcopy(self.state)
            state['resources'][resource_index]['instances'][0]['attributes'][field] = value
            with self.subTest(field=field), self.assertRaises(ConfigError):
                bind_bootstrap_groups(self.values, state)
        self.state['resources'].append(copy.deepcopy(self.state['resources'][1]))
        with self.assertRaisesRegex(ConfigError, 'workspace assignment'):
            bind_bootstrap_groups(self.values, self.state)

    def test_supplemental_role_drift_and_missing_declaration_are_rejected(self):
        bound = bind_bootstrap_groups(self.values, self.state)
        for declaration in ({}, {'dev-demo-admins': {'workspace_permission': 'USER'}}):
            with self.subTest(declaration=declaration), self.assertRaisesRegex(ConfigError, 'supplemental bootstrap'):
                check_ownership(bound, {'02-account': self.state}, {'account_groups': declaration})

    def test_bootstrap_cannot_overlap_other_roots_or_existing_root05(self):
        bound = bind_bootstrap_groups(self.values, self.state)
        for root in ('03-data-access', '04-workspace', ROOT):
            for resource in self.state['resources'][:2]:
                conflict = {'version': 4, 'resources': [resource],
                            'outputs': {'target_identity': {'value': identity(bound)}}}
                with self.subTest(root=root, kind=resource['type']), self.assertRaisesRegex(ConfigError, 'owned'):
                    check_ownership(bound, {'02-account': self.state, root: conflict}, self.supplemental)
        conflict = state_resource('databricks_entitlements', group_id='700')
        with self.assertRaisesRegex(ConfigError, 'entitlements'):
            check_ownership(bound, {'02-account': self.state, ROOT: conflict}, self.supplemental)

    def test_bound_group_id_changes_invalidate_saved_plan(self):
        bound = bind_bootstrap_groups(self.values, self.state)
        expected = {'inputs': bound, 'legacy_states': {'02-account': 'state-hash'}, 'source_digest': 'source'}
        saved = {'binding': copy.deepcopy(expected), 'plan_sha256': hashlib.sha256(b'plan').hexdigest(),
                 'expires_at': (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()}
        expected['inputs']['groups']['admins']['account_group_id'] = '999'
        with self.assertRaisesRegex(ConfigError, 'changed'):
            check_saved_plan(saved, expected, b'plan')

    def test_bootstrap_entitlements_have_a_separate_verified_owner(self):
        bound = bind_bootstrap_groups(self.values, self.state)
        features = state_resource('databricks_entitlements', group_id='700')
        features['outputs'] = {
            'target_identity': {'value': {'environment': 'dev', 'workspace': 'demo',
                **{key: str(bound[key]) for key in ('account_id', 'workspace_id', 'workspace_url')}}},
            'group_ids': {'value': {key: group['account_group_id'] for key, group in bound['groups'].items()}},
        }
        states = {'02-account': self.state, '02-workspace-access': features}
        check_ownership(bound, states, self.supplemental)
        features['outputs']['target_identity']['value']['workspace_id'] = '999'
        with self.assertRaisesRegex(ConfigError, 'Workspace feature state'):
            check_ownership(bound, states, self.supplemental)


class PlanTests(unittest.TestCase):
    def change(self, kind, actions, before=None, after=None):
        return {'resource_changes': [{'mode': 'managed', 'type': kind,
                'change': {'actions': actions, 'before': before, 'after': after}}]}

    def test_grant_revocation_is_supported(self):
        check_plan(self.change('databricks_grant', ['delete']))

    def test_data_object_creation_and_group_retirement_are_rejected(self):
        for kind, actions in [('databricks_catalog', ['create']), ('databricks_schema', ['create']),
                              ('databricks_sql_table', ['create']), ('databricks_group', ['delete']),
                              ('databricks_group', ['delete', 'create']),
                              ('databricks_mws_permission_assignment', ['delete']),
                              ('databricks_entitlements', ['delete'])]:
            with self.subTest(kind=kind, actions=actions), self.assertRaises(ConfigError):
                check_plan(self.change(kind, actions))

    def test_admin_removal_requires_separate_review(self):
        with self.assertRaisesRegex(ConfigError, 'ADMIN removal'):
            check_plan(self.change('databricks_mws_permission_assignment', ['update'],
                                   {'permissions': ['ADMIN']}, {'permissions': ['USER']}))

    def test_saved_plan_is_bound_to_source_inputs_ownership_bytes_and_expiry(self):
        now = datetime.now(timezone.utc)
        expected = {'commit': 'abc', 'source_digest': 'source', 'inputs': {'groups': {}}, 'legacy_states': {'02': 'hash'}}
        saved = {'binding': copy.deepcopy(expected), 'plan_sha256': hashlib.sha256(b'plan').hexdigest(),
                 'expires_at': (now + timedelta(hours=24)).isoformat()}
        check_saved_plan(saved, expected, b'plan', now)
        for key in expected:
            changed = expected | {key: 'changed'}
            with self.subTest(key=key), self.assertRaisesRegex(ConfigError, 'changed'):
                check_saved_plan(saved, changed, b'plan', now)
        with self.assertRaisesRegex(ConfigError, 'changed'):
            check_saved_plan(saved, expected, b'tampered', now)
        with self.assertRaisesRegex(ConfigError, 'expired'):
            check_saved_plan(saved, expected, b'plan', now + timedelta(hours=25))

    def test_apply_requires_main_opt_in_and_real_environment_approval(self):
        env = {'GITHUB_REF': 'refs/heads/main', 'DATABRICKS_PERMISSIONS_APPLY_ENABLED': 'true',
               'GITHUB_REPOSITORY': 'owner/repo', 'GH_TOKEN': 'fake'}
        with patch.dict(os.environ, env, clear=True), patch('subprocess.check_output', return_value='{"protection_rules": []}'):
            with self.assertRaisesRegex(ConfigError, 'require reviewers'):
                require_apply_gate('dev-demo-apply')
        protection = {'can_admins_bypass': False, 'protection_rules': [{'type': 'required_reviewers', 'prevent_self_review': True,
                                           'reviewers': [{'type': 'User', 'reviewer': {'login': 'reviewer'}}]}]}
        with patch.dict(os.environ, env, clear=True), patch('subprocess.check_output', return_value=json.dumps(protection)):
            require_apply_gate('dev-demo-apply')
            os.environ['GITHUB_REF'] = 'refs/heads/feature'
            with self.assertRaisesRegex(ConfigError, 'only on main'):
                require_apply_gate('dev-demo-apply')
            os.environ['GITHUB_REF'] = 'refs/heads/main'
            os.environ['DATABRICKS_PERMISSIONS_APPLY_ENABLED'] = 'false'
            with self.assertRaisesRegex(ConfigError, 'APPLY_ENABLED'):
                require_apply_gate('dev-demo-apply')


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.values = render(load_bundle())
        for group in self.values['groups'].values():
            group['lifecycle'] = 'create'
        self.account, self.workspace = Mock(), Mock()
        self.account.groups.list.return_value = []
        self.workspace.metastores.current.return_value = SimpleNamespace(
            workspace_id=self.values['workspace_id'], metastore_id=self.values['metastore_id'])
        self.workspace.grants.get.return_value = SimpleNamespace(privilege_assignments=[])
        self.sdk = SimpleNamespace(AccountClient=Mock(return_value=self.account), WorkspaceClient=Mock(return_value=self.workspace))
        self.catalog = SimpleNamespace(SecurableType=SimpleNamespace(CATALOG='CATALOG', SCHEMA='SCHEMA', TABLE='TABLE'))
        self.patches = [patch.dict(os.environ, {'DATABRICKS_CLIENT_ID': 'fake', 'DATABRICKS_CLIENT_SECRET': 'fake'}),
                        patch.dict(sys.modules, {'databricks.sdk': self.sdk, 'databricks.sdk.service.catalog': self.catalog}),
                        patch('terraform_permissions.verify_identity', return_value=[])]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def test_missing_existing_table_fails_without_creating_it(self):
        self.workspace.tables.get.side_effect = PermissionError('sensitive-sdk-detail')
        with self.assertRaisesRegex(ConfigError, 'existing table dev_demo.gold.sales_summary') as error:
            preflight(self.values, None)
        self.assertNotIn('sensitive-sdk-detail', str(error.exception))
        self.workspace.tables.create.assert_not_called()

    def test_existing_group_is_not_silently_adopted(self):
        self.account.groups.list.return_value = [SimpleNamespace(id='777')]
        with self.assertRaisesRegex(ConfigError, 'reviewed import'):
            preflight(self.values, None)

    def test_existing_direct_grants_require_import(self):
        self.workspace.grants.get.return_value = SimpleNamespace(privilege_assignments=[
            SimpleNamespace(principal='dev-demo-engineers', privileges=['USE_CATALOG'])])
        with self.assertRaisesRegex(ConfigError, 'direct grant requires reviewed import'):
            preflight(self.values, None)

    def test_terraform_bootstrap_requires_bound_unique_live_identity(self):
        group = self.values['groups']['admins']
        group.update(lifecycle='terraform', account_group_id='700')
        self.values['groups'] = {'admins': group}
        self.values['grants'] = {}
        for found in ([], [SimpleNamespace(id='999')], [SimpleNamespace(id='700'), SimpleNamespace(id='700')]):
            self.account.groups.list.return_value = found
            with self.subTest(found=found), self.assertRaisesRegex(ConfigError, 'Terraform group identity mismatch'):
                preflight(self.values, None)
        self.account.groups.list.return_value = [SimpleNamespace(id='700')]
        preflight(self.values, None)
        group.pop('account_group_id')
        with self.assertRaisesRegex(ConfigError, 'Terraform group identity mismatch'):
            preflight(self.values, None)

    def test_wrong_metastore_stops_before_group_and_object_reads(self):
        self.workspace.metastores.current.return_value.metastore_id = 'different'
        with self.assertRaisesRegex(ConfigError, 'registered target'):
            preflight(self.values, None)
        self.account.groups.list.assert_not_called()
        self.workspace.catalogs.get.assert_not_called()
