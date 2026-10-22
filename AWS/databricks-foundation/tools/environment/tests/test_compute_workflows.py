from pathlib import Path
from fnmatch import fnmatchcase
import unittest

import yaml


WORKFLOWS = Path(__file__).resolve().parents[5] / '.github/workflows'


def workflow(name):
    return yaml.load((WORKFLOWS / name).read_text(), Loader=yaml.BaseLoader)


class ComputeWorkflowTests(unittest.TestCase):
    def test_provision_compute_follows_successful_features_on_manual_main_demo(self):
        job = workflow('environment-provision.yml')['jobs']['workspace_compute']
        self.assertEqual(job['needs'], 'workspace_access')
        self.assertEqual(job['uses'], './.github/workflows/environment-compute.yml')
        for guard in ('!cancelled()', "needs.workspace_access.result == 'success'",
                      "github.ref == 'refs/heads/main'", "github.event_name == 'workflow_dispatch'",
                      "inputs.target_environment == 'dev'", "inputs.target_workspace == 'demo'"):
            self.assertIn(guard, job['if'])
        self.assertEqual(job['with']['deploy'], '${{ inputs.deploy }}')
        self.assertEqual(job['with']['confirm_environment'], '${{ inputs.confirm_environment }}')

    def test_retirement_orders_compute_before_features_and_preserves_preview_stop(self):
        jobs = workflow('environment-deprovision.yml')['jobs']
        compute = jobs['workspace_compute']
        self.assertEqual(compute['with']['retire'], 'true')
        self.assertEqual(compute['with']['deploy'], '${{ inputs.execute_destroy }}')
        self.assertEqual(compute['with']['confirm_environment'], '${{ inputs.confirm_environment }}')
        self.assertEqual(jobs['workspace_access']['needs'], 'workspace_compute')
        for condition in ('!cancelled()', "needs.workspace_compute.result == 'success'",
                          "needs.workspace_compute.result == 'skipped'",
                          "github.ref == 'refs/heads/main'", "github.event_name == 'workflow_dispatch'",
                          "inputs.target_environment == 'dev'", "inputs.target_workspace == 'demo'"):
            self.assertIn(condition, jobs['workspace_access']['if'])
        self.assertEqual(jobs['account']['needs'], 'workspace_access')
        self.assertIn('inputs.execute_destroy ||', jobs['account']['if'])
        for name in ('workspace_access', 'account', 'infra'):
            self.assertIn('!cancelled()', jobs[name]['if'])

    def test_reusable_ancestors_handle_skipped_jobs_but_block_failed_plans(self):
        for name, predecessor, mutation in (
            ('environment-root.yml', 'plan', 'apply'),
            ('environment-destroy-root.yml', 'preview', 'destroy'),
            ('environment-workspace-access.yml', 'plan', 'apply'),
        ):
            jobs = workflow(name)['jobs']
            for job in jobs.values():
                self.assertIn('!cancelled()', job['if'])
            self.assertIn(f"needs.{predecessor}.result == 'success'", jobs[mutation]['if'])

    def test_compute_workflow_scopes_execution_and_keeps_same_run_plan_only_artifacts(self):
        definition = workflow('environment-compute.yml')
        inputs = definition['on']['workflow_call']['inputs']
        self.assertEqual(inputs['deploy']['default'], 'false')
        self.assertEqual(inputs['retire']['default'], 'false')
        jobs = definition['jobs']
        for name, job in jobs.items():
            for guard in ('!cancelled()', "github.ref == 'refs/heads/main'",
                          "github.event_name == 'workflow_dispatch'", "inputs.target_environment == 'dev'",
                          "inputs.target_workspace == 'demo'"):
                self.assertIn(guard, job['if'])
            commands = '\n'.join(step.get('run', '') for step in job['steps'])
            self.assertIn('terraform_compute.py', commands)
            self.assertIn('--confirm-environment "$CONFIRM_ENVIRONMENT"', commands)
            self.assertEqual(job['env']['DATABRICKS_AUTH_TYPE'], 'oauth-m2m')
        self.assertEqual(jobs['apply']['needs'], 'plan')
        self.assertIn("needs.plan.result == 'success'", jobs['apply']['if'])
        self.assertIn('inputs.deploy', jobs['apply']['if'])
        self.assertEqual(jobs['apply']['env']['GH_TOKEN'], '${{ github.token }}')
        self.assertEqual(jobs['apply']['env']['ENVIRONMENT_YAML_DESTROY_ENABLED'], '${{ vars.ENVIRONMENT_YAML_DESTROY_ENABLED }}')
        upload = next(step for step in jobs['plan']['steps'] if 'upload-artifact' in step.get('uses', ''))
        download = next(step for step in jobs['apply']['steps'] if 'download-artifact' in step.get('uses', ''))
        self.assertEqual(upload['with']['name'], 'dev-demo-compute-retire-${{ inputs.retire }}')
        self.assertEqual(download['with']['name'], upload['with']['name'])
        self.assertNotIn('run-id', download['with'])
        self.assertEqual(upload['with']['retention-days'], '1')
        self.assertEqual([Path(p).name for p in upload['with']['path'].splitlines()], ['terraform.tfplan', 'manifest.json'])

    def test_ci_exercises_compute_modules_and_rendered_root_inputs_without_credentials(self):
        definition = workflow('environment-validation.yml')
        for event in ('pull_request', 'push'):
            for path in ('.github/workflows/environment-compute.yml',
                         'AWS/databricks-foundation/environments/dev/04-workspace/**',
                         'AWS/databricks-foundation/modules/databricks/cluster-policies/**',
                         'AWS/databricks-foundation/modules/databricks/sql-warehouses/**'):
                self.assertTrue(any(fnmatchcase(path, pattern)
                                    for pattern in definition['on'][event]['paths']), path)
        job = definition['jobs']['terraform-permissions']
        for directory in ('modules/databricks/cluster-policies', 'modules/databricks/sql-warehouses',
                          'environments/dev/04-workspace'):
            self.assertIn(directory, job['strategy']['matrix']['directory'])
        generated = next(step for step in job['steps'] if 'terraform_compute.py render' in step.get('run', ''))
        self.assertIn("matrix.directory == 'environments/dev/04-workspace'", generated['if'])
        self.assertIn('-test-directory=generated-tests', generated['run'])
        self.assertIn('-var-file="$RUNNER_TEMP/compute-inputs/compute.tfvars.json"', generated['run'])
