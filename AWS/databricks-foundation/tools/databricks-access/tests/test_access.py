import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from configuration import ConfigError, FOUNDATION, load_bundle, load_yaml
from desired import preview


class DemoAccessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        shutil.copytree(FOUNDATION / 'platform', self.root / 'platform')
        shutil.copytree(FOUNDATION / 'workloads', self.root / 'workloads')

    def bundle(self):
        return load_bundle(self.root)

    def change(self, path, mutate):
        full_path = self.root / 'platform' / path
        document = load_yaml(full_path)
        mutate(document)
        full_path.write_text(yaml.safe_dump(document, sort_keys=False))

    def grant(self, result, principal, kind, name):
        return next(item for item in result['grants'] if item['principal'] == principal
                    and item['object_type'] == kind and item['object_name'] == name)

    def test_demo_expands_exact_writer_and_reader_permissions(self):
        result = preview(self.bundle())
        engineer = 'dev-demo-engineers'
        self.assertEqual(self.grant(result, engineer, 'schema', 'dev_demo.bronze')['privileges'],
                         ['CREATE_TABLE', 'MODIFY', 'SELECT', 'USE_SCHEMA'])
        self.assertEqual(self.grant(result, engineer, 'catalog', 'dev_demo')['privileges'], ['USE_CATALOG'])
        self.assertEqual(self.grant(result, engineer, 'schema', 'dev_demo.gold')['privileges'], ['USE_SCHEMA'])
        self.assertEqual(self.grant(result, engineer, 'table', 'dev_demo.gold.sales_summary')['privileges'], ['SELECT'])
        analyst = [item for item in result['grants'] if item['principal'] == 'dev-demo-analysts']
        self.assertEqual({item['object_name'] for item in analyst}, {'dev_demo', 'dev_demo.gold'})
        self.assertFalse(any('MODIFY' in item['privileges'] for item in analyst))
        self.assertFalse(any(item['principal'] == 'dev-demo-admins' for item in result['grants']))
        self.assertEqual(result['groups']['admins']['workspace_role'], 'ADMIN')

    def test_ml_writes_only_designated_schema(self):
        result = preview(self.bundle())
        writes = [item['object_name'] for item in result['grants']
                  if item['principal'] == 'dev-demo-ml' and 'MODIFY' in item['privileges']]
        self.assertEqual(writes, ['dev_demo.ml'])

    def test_compute_acls_and_constraints(self):
        result = preview(self.bundle())
        engineering = result['cluster_policies']['engineering-standard']
        self.assertEqual(engineering['permissions'], {'dev-demo-engineers': 'CAN_USE'})
        self.assertEqual(result['sql_warehouses']['analytics']['permissions']['dev-demo-admins'], 'CAN_MANAGE')
        definition = engineering['definition']
        self.assertEqual(definition['spark_version']['values'], ['16.4.x-scala2.12'])
        self.assertEqual(definition['use_ml_runtime']['value'], False)
        self.assertEqual(result['cluster_policies']['ml-standard']['definition']['use_ml_runtime']['value'], True)
        self.assertEqual(definition['node_type_id']['values'], ['m5d.large', 'm5d.xlarge'])
        self.assertEqual(definition['autoscale.min_workers'], {'type': 'fixed', 'value': 1})
        self.assertEqual(definition['autoscale.max_workers']['maxValue'], 2)
        self.assertEqual(definition['is_single_node']['value'], False)
        for field in ('num_workers', 'instance_pool_id', 'driver_instance_pool_id',
                      'docker_image.url', 'aws_attributes.instance_profile_arn'):
            self.assertEqual(definition[field]['type'], 'forbidden')
        for field in ('worker_node_type_flexibility', 'driver_node_type_flexibility'):
            self.assertEqual(definition[f'{field}.alternate_node_type_ids'], {'type': 'fixed', 'value': ''})
        for variant in ('workspace', 'volumes', 's3', 'file'):
            self.assertEqual(definition[f'init_scripts.*.{variant}.destination']['type'], 'forbidden')

    def test_preview_is_explicitly_non_executable(self):
        result = preview(self.bundle())
        self.assertEqual(result['kind'], 'offline-desired-state')
        self.assertIs(result['executable'], False)
        self.assertTrue(any('OFFLINE PREVIEW ONLY' in warning for warning in result['warnings']))
        self.assertTrue(any('current and future' in warning for warning in result['warnings']))

    def test_order_does_not_change_preview(self):
        before = preview(self.bundle())
        for path in self.root.rglob('*.yaml'):
            if not any(part in path.parts for part in ('workloads', 'platform', 'compute')):
                continue
            document = load_yaml(path)

            def reverse(value):
                if isinstance(value, dict):
                    return {key: reverse(item) for key, item in reversed(list(value.items()))}
                if isinstance(value, list):
                    return [reverse(item) for item in reversed(value)]
                return value

            path.write_text(yaml.safe_dump(reverse(document), sort_keys=False))
        after = preview(self.bundle())
        self.assertEqual(json.dumps(before, sort_keys=True), json.dumps(after, sort_keys=True))

    def test_multiple_requests_union_with_source_tracking(self):
        self.change('access/resources/dev/demo.yaml',
                    lambda d: d['workloads']['data-analytics'].update(principal='engineers'))
        self.change('../workloads/data-analytics/dev-demo.yaml',
                    lambda d: d.update(persona='engineers', data_access=[
                        {'id': 'also-bronze', 'catalog': 'dev_demo', 'schema': 'bronze',
                         'access': 'reader', 'reason': 'Cross-workload validation'}]))
        result = preview(self.bundle())
        grant = self.grant(result, 'dev-demo-engineers', 'schema', 'dev_demo.bronze')
        self.assertEqual(grant['sources'], ['data-analytics/also-bronze', 'data-engineering/bronze-write'])
        self.assertEqual(grant['privileges'], ['CREATE_TABLE', 'MODIFY', 'SELECT', 'USE_SCHEMA'])

    def test_empty_workload_grants_do_not_clear_other_workloads(self):
        self.change('../workloads/data-engineering/dev-demo.yaml', lambda d: d.update(data_access=[]))
        result = preview(self.bundle())
        self.assertFalse(any(item['principal'] == 'dev-demo-engineers' for item in result['grants']))
        self.assertTrue(any(item['principal'] == 'dev-demo-analysts' for item in result['grants']))
        self.assertFalse(result['executable'])  # It does not claim live revocations.

    def test_duplicate_key_and_alias_rejected(self):
        path = self.root / 'bad.yaml'
        for contents in ('version: 1\nversion: 1\n', 'one: &ref [SELECT]\ntwo: *ref\n', '1: value\n'):
            with self.subTest(contents=contents):
                path.write_text(contents)
                with self.assertRaises(ConfigError):
                    load_yaml(path)

    def test_workload_cannot_choose_compute_group_or_raw_privileges(self):
        path = '../workloads/data-engineering/dev-demo.yaml'
        for field, value in [('principal', 'admins'), ('privileges', ['ALL_PRIVILEGES']),
                             ('cluster_policies', ['ml-standard']), ('compute_access', {}),
                             ('capabilities', {'sql': True}), ('feature_access', True)]:
            with self.subTest(field=field):
                original = (self.root / 'platform' / path).read_text()
                self.change(path, lambda d: d.update({field: value}))
                with self.assertRaises(ConfigError):
                    self.bundle()
                (self.root / 'platform' / path).write_text(original)

    def test_workload_cannot_select_a_different_persona(self):
        self.change('../workloads/data-engineering/dev-demo.yaml', lambda d: d.update(persona='admins'))
        with self.assertRaisesRegex(ConfigError, 'platform-approved persona'):
            self.bundle()

    def test_reader_persona_cannot_request_writer(self):
        self.change('../workloads/data-analytics/dev-demo.yaml', lambda d: d['data_access'][0].update(access='writer'))
        with self.assertRaisesRegex(ConfigError, 'persona cannot request'):
            self.bundle()

    def test_engineer_cannot_write_gold(self):
        self.change('../workloads/data-engineering/dev-demo.yaml',
                    lambda d: d['data_access'][0].update(schema='gold'))
        with self.assertRaisesRegex(ConfigError, 'resource does not permit'):
            self.bundle()

    def test_unknown_catalog_schema_persona_and_wildcards_fail(self):
        path = '../workloads/data-engineering/dev-demo.yaml'
        original = (self.root / 'platform' / path).read_text()
        mutations = [lambda d: d['data_access'][0].update(catalog='other'),
                     lambda d: d['data_access'][0].update(schema='other'),
                     lambda d: d.update(persona='unknown'),
                     lambda d: d['data_access'][0].update(catalog='*')]
        for mutate in mutations:
            self.change(path, mutate)
            with self.assertRaises(ConfigError):
                self.bundle()
            (self.root / 'platform' / path).write_text(original)

    def test_catalog_writer_is_not_a_valid_package(self):
        self.change('../workloads/data-engineering/dev-demo.yaml',
                    lambda d: d['data_access'][0].pop('schema'))
        with self.assertRaisesRegex(ConfigError, 'does not support catalog'):
            self.bundle()

    def test_duplicate_request_id_fails(self):
        self.change('../workloads/data-analytics/dev-demo.yaml', lambda d: d['data_access'].append(copy.deepcopy(d['data_access'][0])))
        with self.assertRaisesRegex(ConfigError, 'Duplicate grant ID'):
            self.bundle()

    def test_workload_cannot_override_folder_identity_or_target(self):
        for field, value in [('workload', 'data-engineering'), ('workspace', 'sandbox'), ('environment', 'production')]:
            path = self.root / 'platform/../workloads/data-analytics/dev-demo.yaml'
            original = path.read_text()
            self.change('../workloads/data-analytics/dev-demo.yaml', lambda d: d.update({field: value}))
            with self.assertRaises(ConfigError):
                self.bundle()
            path.write_text(original)

    def test_files_cannot_be_silently_ignored(self):
        (self.root / 'workloads/data-analytics/ignored.yml').write_text('version: 1\n')
        with self.assertRaisesRegex(ConfigError, 'dev-demo.yaml only'):
            self.bundle()

    def test_unknown_workload_folder_is_rejected(self):
        (self.root / 'workloads/unregistered').mkdir()
        with self.assertRaisesRegex(ConfigError, 'Unknown workload folder'):
            self.bundle()

    def test_legacy_access_layout_is_rejected(self):
        legacy = self.root / 'config/access/dev/demo'
        legacy.mkdir(parents=True, exist_ok=True)
        (legacy / 'analytics.yaml').write_text('version: 1\n')
        with self.assertRaisesRegex(ConfigError, 'Legacy config/access'):
            self.bundle()

    def test_group_ids_and_names_are_unambiguous(self):
        self.change('access/principals/dev/demo.yaml',
                    lambda d: d['groups']['ml'].update(display_name='dev-demo-engineers'))
        with self.assertRaisesRegex(ConfigError, 'Duplicate group display name'):
            self.bundle()

    def test_external_group_requires_explicit_id(self):
        self.change('access/principals/dev/demo.yaml', lambda d: d['groups']['ml'].update(
            lifecycle='external', display_name='dev-demo-external-ml'))
        with self.assertRaisesRegex(ConfigError, 'external requires'):
            self.bundle()
        self.change('access/principals/dev/demo.yaml', lambda d: d['groups']['ml'].update(account_group_id='12345'))
        self.bundle()

    def test_bootstrap_groups_remain_terraform_owned(self):
        result = preview(self.bundle())
        self.assertEqual(len(result['groups']), 4)
        for key, group in result['groups'].items():
            self.assertEqual(group['lifecycle'], 'terraform')
            self.assertEqual(group['workspace_access_owner'], '02-account')
            self.assertEqual(group['workspace_role'], 'ADMIN' if key == 'admins' else 'USER')

    def test_bootstrap_role_drift_missing_group_and_membership_are_rejected(self):
        path = self.root / 'platform/terraform-inputs/dev/demo.02-account.json'
        original = path.read_text()
        mutations = [
            lambda groups: groups['dev-demo-engineers'].update(workspace_permission='ADMIN'),
            lambda groups: groups.pop('dev-demo-ml'),
            lambda groups: groups['dev-demo-admins'].update(member_ids={'someone': '123'}),
        ]
        for mutate in mutations:
            document = json.loads(original)
            mutate(document['account_groups'])
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ConfigError, 'Terraform workspace access'):
                self.bundle()
        path.write_text(original)

    def test_terraform_group_cannot_be_claimed_for_api_creation(self):
        self.change('access/principals/dev/demo.yaml',
                    lambda d: d['groups']['ml'].update(lifecycle='create'))
        with self.assertRaisesRegex(ConfigError, 'already Terraform-owned'):
            self.bundle()

    def test_non_admin_cannot_gain_admin_or_unrestricted_compute(self):
        path = 'access/roles.yaml'
        original = (self.root / 'platform' / path).read_text()
        self.change(path, lambda d: d['personas']['engineers'].update(workspace_role='ADMIN'))
        with self.assertRaisesRegex(ConfigError, 'Only the admins'):
            self.bundle()
        (self.root / 'platform' / path).write_text(original)
        self.change(path, lambda d: d['personas']['engineers']['entitlements'].update(allow_cluster_create=True))
        with self.assertRaises(ConfigError):
            self.bundle()

    def test_unknown_policy_package_and_owner_fail(self):
        changes = [
            ('access/roles.yaml', lambda d: d['personas']['engineers']['cluster_policies'].append('missing')),
            ('access/roles.yaml', lambda d: d['personas']['engineers']['allowed_packages'].append('missing')),
            ('access/resources/dev/demo.yaml', lambda d: d['datasets']['dev_demo'].update(approval_owner='missing')),
        ]
        for path, mutate in changes:
            original = (self.root / 'platform' / path).read_text()
            self.change(path, mutate)
            with self.assertRaises(ConfigError):
                self.bundle()
            (self.root / 'platform' / path).write_text(original)

    def test_compute_defaults_limits_and_cpu_ml_mode_fail(self):
        path = 'compute/dev.yaml'
        original = (self.root / 'platform' / path).read_text()
        mutations = [
            lambda d: d['cluster_policies']['engineering-standard']['runtime'].update(default_version='missing'),
            lambda d: d['cluster_policies']['engineering-standard']['worker_nodes'].update(default_type='m5d.2xlarge'),
            lambda d: d['cluster_policies']['engineering-standard']['autoscaling'].update(min_workers=3),
            lambda d: d['cluster_policies']['ml-standard'].update(data_security_mode='USER_ISOLATION'),
            lambda d: d['sql_warehouses']['analytics'].update(min_clusters=2),
            lambda d: d['cluster_policies']['engineering-standard'].update(definition={'num_workers': 100}),
            lambda d: d['cluster_policies']['engineering-standard']['worker_nodes'].update(allowed_types=['p4d.24xlarge']),
        ]
        for mutate in mutations:
            self.change(path, mutate)
            with self.assertRaises(ConfigError):
                self.bundle()
            (self.root / 'platform' / path).write_text(original)

    def test_target_must_match_provisioning_and_inactive_examples_cannot_be_activated(self):
        path = 'access/targets/dev/demo.yaml'
        original = (self.root / 'platform' / path).read_text()
        self.change(path, lambda d: d.update(account_id='11111111-1111-1111-1111-111111111111'))
        with self.assertRaisesRegex(ConfigError, 'account_id must match'):
            self.bundle()
        (self.root / 'platform' / path).write_text(original)
        self.change(path, lambda d: d.update(active=True, workspace_id='0'))
        with self.assertRaisesRegex(ConfigError, 'active target requires real'):
            self.bundle()

    def test_unsupported_targets_fail(self):
        for environment, workspace in [('production', 'demo'), ('staging', 'demo'), ('dev', 'sandbox'), ('../dev', 'demo')]:
            with self.assertRaisesRegex(ConfigError, 'dev/demo only'):
                load_bundle(self.root, environment, workspace)

    def test_schemas_are_valid_json_schema(self):
        import jsonschema
        schema = json.loads((HERE / 'schema.json').read_text())
        jsonschema.Draft202012Validator.check_schema(schema)


class CommandTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(HERE / 'access.py'), *args],
                              text=True, capture_output=True, check=False)

    def test_cli_validate_and_preview(self):
        result = self.run_cli('validate', '--environment', 'dev', '--workspace', 'demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_cli('preview', '--environment', 'dev', '--workspace', 'demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIs(json.loads(result.stdout)['executable'], False)

    def test_no_apply_or_misleading_live_plan_command(self):
        for command in ('apply', 'plan', 'destroy'):
            result = self.run_cli(command, '--environment', 'dev', '--workspace', 'demo')
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
