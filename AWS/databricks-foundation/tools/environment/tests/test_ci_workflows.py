from pathlib import Path
import unittest

import yaml


WORKFLOWS = Path(__file__).resolve().parents[5] / '.github/workflows'


def workflow(name):
    return yaml.load((WORKFLOWS / name).read_text(), Loader=yaml.BaseLoader)


class CIWorkflowTests(unittest.TestCase):
    def test_only_validation_runs_automatically_and_has_no_cloud_credentials(self):
        automatic = []
        for path in WORKFLOWS.glob('*.yml'):
            definition = workflow(path.name)
            if {'push', 'pull_request'} & definition['on'].keys():
                automatic.append(path.name)
        self.assertEqual(automatic, ['environment-validation.yml'])
        definition = workflow(automatic[0])
        self.assertEqual(definition['permissions'], {'contents': 'read'})
        self.assertNotIn('secrets.', (WORKFLOWS / automatic[0]).read_text())
        for job in definition['jobs'].values():
            self.assertNotIn('environment', job)
            self.assertFalse(any('configure-aws-credentials' in step.get('uses', '')
                                 for step in job['steps']))

    def test_validation_runs_each_python_suite_once_and_preserves_renderers(self):
        definition = workflow('environment-validation.yml')
        self.assertEqual(definition['jobs']['terraform-permissions']['strategy']['fail-fast'], 'false')
        commands = '\n'.join(step.get('run', '')
                             for job in definition['jobs'].values()
                             for step in job['steps'])
        for suite in ('environment', 'databricks-access'):
            self.assertEqual(commands.count(f'unittest discover -s AWS/databricks-foundation/tools/{suite}/tests'), 1)
        for renderer in ('terraform_entitlements.py', 'terraform_compute.py', 'terraform_permissions.py'):
            self.assertIn(f'{renderer} render', commands)
        for operation in ('validate', 'preview'):
            self.assertIn(f'access.py {operation} --environment dev --workspace demo', commands)
        for root in ('modules/databricks/workspace-access', 'modules/databricks/uc-permissions',
                     'environments/dev/05-permissions', 'modules/databricks/cluster-policies',
                     'modules/databricks/sql-warehouses', 'environments/dev/04-workspace'):
            self.assertIn(root, definition['jobs']['terraform-permissions']['strategy']['matrix']['directory'])

    def test_permissions_and_diagnostics_require_manual_main_and_separate_operations(self):
        definition = workflow('databricks-permissions.yml')
        self.assertEqual(list(definition['on']), ['workflow_dispatch'])
        inputs = definition['on']['workflow_dispatch']['inputs']
        self.assertEqual(inputs['operation']['default'], 'plan')
        self.assertEqual(inputs['deploy']['default'], 'false')
        self.assertEqual(inputs['check_metastore']['default'], 'false')
        for name, job in definition['jobs'].items():
            self.assertIn("github.event_name == 'workflow_dispatch'", job['if'])
            self.assertIn("github.ref == 'refs/heads/main'", job['if'])
            operation = 'diagnostics' if name == 'diagnostics' else 'plan'
            self.assertIn(f"inputs.operation == '{operation}'", job['if'])
        apply = definition['jobs']['apply']
        self.assertEqual(apply['needs'], 'plan')
        self.assertIn('inputs.deploy', apply['if'])
        self.assertEqual(apply['environment'], 'dev-demo-apply')
        upload = next(step for step in definition['jobs']['plan']['steps']
                      if 'upload-artifact' in step.get('uses', ''))
        download = next(step for step in apply['steps'] if 'download-artifact' in step.get('uses', ''))
        self.assertEqual(upload['with']['name'], download['with']['name'])
        self.assertNotIn('run-id', download['with'])
        self.assertIn('require_apply_gate', '\n'.join(step.get('run', '') for step in apply['steps']))

    def test_diagnostics_use_operator_target_and_deployment_oidc_role(self):
        definition = workflow('databricks-permissions.yml')
        inputs = definition['on']['workflow_dispatch']['inputs']
        self.assertEqual(inputs['workspace_id']['default'], '')
        self.assertEqual(inputs['workspace_url']['default'], '')
        steps = definition['jobs']['diagnostics']['steps']
        credentials = next(step for step in steps if 'configure-aws-credentials' in step.get('uses', ''))
        self.assertEqual(credentials['with']['role-to-assume'], '${{ vars.AWS_DEPLOYMENT_ROLE_ARN }}')
        commands = '\n'.join(step.get('run', '') for step in steps)
        self.assertIn('aws sts get-caller-identity', commands)
        self.assertIn('identity_check.py', commands)
        self.assertIn('--workspace-id "$WORKSPACE_ID" --workspace-url "$WORKSPACE_URL"', commands)
        self.assertNotIn('terraform_permissions.py', commands)
