import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import environment

EXAMPLE = TOOLS.parents[1] / 'platform/environments/dev/shared.yaml'


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.config = environment.load(EXAMPLE)
        self.config['environment']['aws_account_id'] = '123456789012'
        self.config['environment']['deployment_role_arn'] = 'arn:aws:iam::123456789012:role/deployer'
        self.config['databricks']['account_id'] = '12345678-1234-1234-1234-123456789abc'
        self.config['storage']['workspace_bucket_name'] = 'acme-dev-workspace-123456789012'

    def test_valid_environment_renders_existing_root_inputs(self):
        environment.validate(self.config)
        roots = environment.render(self.config)
        self.assertEqual(roots['01-infra']['vpc_cidr_block'], '10.40.0.0/16')
        self.assertEqual(roots['01-infra']['workspace_subnets']['b']['cidr_block'], '10.40.16.0/20')
        self.assertEqual(roots['02-account']['workspace_name'], 'dev-shared')
        self.assertEqual(roots['01-infra']['workspace_key'], 'shared')
        self.assertNotIn('deployment_role_arn', roots['01-infra'])

    def test_invalid_inputs(self):
        cases = [
            ('version', lambda c: c.update(version=1)),
            ('missing workspace', lambda c: c.pop('workspace')),
            ('workspace traversal', lambda c: c['workspace'].update(name='../sandbox')),
            ('workspace case', lambda c: c['workspace'].update(name='Sandbox')),
            ('unknown', lambda c: c['features'].update(private_link=True)),
            ('string boolean', lambda c: c['features'].update(observability='false')),
            ('numeric account', lambda c: c['environment'].update(aws_account_id=111111111111)),
            ('role account', lambda c: c['environment'].update(deployment_role_arn='arn:aws:iam::222222222222:role/deployer')),
            ('unsupported environment', lambda c: c['environment'].update(name='qa')),
            ('unsupported region', lambda c: c['environment'].update(aws_region='eu-north-1')),
            ('overlap', lambda c: c['network']['nat_subnets']['a'].update(cidr_block='10.40.0.0/24')),
            ('outside vpc', lambda c: c['network']['nat_subnets']['a'].update(cidr_block='10.41.0.0/24')),
            ('noncanonical', lambda c: c['network']['nat_subnets']['a'].update(cidr_block='10.40.32.1/24')),
            ('wrong az', lambda c: c['network']['endpoint_subnets']['a'].update(availability_zone='eu-central-1a')),
            ('one workspace az', lambda c: c['network']['workspace_subnets']['b'].update(availability_zone='eu-west-1a')),
            ('cross az nat', lambda c: c['network']['workspace_subnet_nat_gateway_keys'].update(a='b')),
            ('single NAT has two subnets', lambda c: c['network']['nat_subnets'].update(b={'availability_zone': 'eu-west-1b', 'cidr_block': '10.40.48.0/24'})),
            ('per AZ has cross az mapping', lambda c: (c['network'].update(nat_gateway_mode='per_az'), c['network']['nat_subnets'].update(b={'availability_zone': 'eu-west-1b', 'cidr_block': '10.40.48.0/24'}), c['network']['workspace_subnet_nat_gateway_keys'].update(b='a'))),
            ('missing mapping', lambda c: c['network']['workspace_subnet_nat_gateway_keys'].pop('a')),
            ('small workspace subnet', lambda c: c['network']['workspace_subnets']['a'].update(cidr_block='10.40.0.0/28')),
            ('invalid bucket', lambda c: c['storage'].update(workspace_bucket_name='Invalid_Bucket')),
            ('secret field', lambda c: c['environment'].update(aws_access_key_id='secret')),
        ]
        for name, change in cases:
            with self.subTest(name=name):
                config = copy.deepcopy(self.config)
                change(config)
                with self.assertRaises(environment.ConfigError):
                    environment.validate(config)

    def test_example_requires_explicit_example_mode(self):
        with self.assertRaises(environment.ConfigError):
            environment.validate(environment.load(EXAMPLE))
        environment.validate(environment.load(EXAMPLE), example=True)

    def test_workspace_and_environment_each_change_state_namespace_and_names(self):
        deployments = []
        for env, workspace in [('dev', 'shared'), ('dev', 'sandbox'), ('staging', 'sandbox')]:
            config = copy.deepcopy(self.config)
            config['environment']['name'] = env
            config['workspace']['name'] = workspace
            environment.validate(config)
            keys = environment.state_keys(config)
            self.assertEqual(keys['01-infra'], f'databricks/{env}/{workspace}/01-infra.tfstate')
            self.assertEqual(len(set(keys.values())), 4)
            rendered = environment.render(config)
            self.assertEqual(rendered['02-account']['workspace_name'], f'{env}-{workspace}')
            deployments.extend(keys.values())
        self.assertEqual(len(set(deployments)), 12)

    def test_staging_and_production_environment_names_are_valid(self):
        for name in ('staging', 'production'):
            with self.subTest(name=name):
                config = copy.deepcopy(self.config)
                config['environment']['name'] = name
                environment.validate(config)

    def test_duplicate_keys_and_unsafe_yaml_fail(self):
        for source in ['version: 1\nversion: 2\n', 'a: {x: 1, x: 2}\n', 'a: !!python/object:object {}\n', 'a: &a [*a]\n', 'true: value\n']:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'bad.yaml'
                path.write_text(source)
                with self.assertRaises(environment.ConfigError):
                    environment.load(path)

    def test_render_is_order_independent(self):
        reversed_config = dict(reversed(list(self.config.items())))
        self.assertEqual(json.dumps(environment.render(self.config), sort_keys=True), json.dumps(environment.render(reversed_config), sort_keys=True))

    def test_cli_render_writes_deterministic_root_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / 'dev.yaml'
            output = Path(tmp) / 'rendered'
            command = [sys.executable, str(TOOLS / 'environment.py'), 'render', str(config), '--output', str(output)]
            config.write_text(yaml.safe_dump(self.config, sort_keys=False))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            infra_path = output / '01-infra.tfvars.json'
            first = infra_path.read_bytes()
            values = json.loads(first)
            self.assertEqual(values['aws_region'], 'eu-west-1')
            self.assertFalse(values['enable_customer_managed_kms'])
            self.assertEqual(json.loads((output / '02-account.tfvars.json').read_text())['workspace_name'], 'dev-shared')
            config.write_text(yaml.safe_dump(self.config, sort_keys=True))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(first, infra_path.read_bytes())

    def test_example_mode_cannot_render_deployment_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'rendered'
            result = subprocess.run([sys.executable, str(TOOLS / 'environment.py'), 'render', str(EXAMPLE), '--example', '--output', str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_cli_validation_does_not_execute_terraform(self):
        result = subprocess.run([sys.executable, str(TOOLS / 'environment.py'), 'validate', str(EXAMPLE), '--example'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Valid', result.stdout)


if __name__ == '__main__':
    unittest.main()
