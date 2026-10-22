from pathlib import Path
import unittest

import yaml


WORKFLOWS = Path(__file__).resolve().parents[5] / '.github/workflows'


def workflow(name):
    return yaml.load((WORKFLOWS / name).read_text(), Loader=yaml.BaseLoader)


class WorkspaceAccessWorkflowTests(unittest.TestCase):
    def test_single_admin_policy_is_checked_before_infra_for_demo_deploy(self):
        definition = workflow('environment-provision.yml')
        jobs = definition['jobs']
        self.assertEqual(jobs['infra']['needs'], 'approval_preflight')
        check = next(step for step in jobs['approval_preflight']['steps']
                     if 'check-approval' in step.get('run', ''))
        for condition in ('inputs.deploy', "github.ref == 'refs/heads/main'",
                          "inputs.target_environment == 'dev'", "inputs.target_workspace == 'demo'"):
            self.assertIn(condition, jobs['approval_preflight']['if'])
        self.assertEqual(check['env']['GH_TOKEN'], '${{ github.token }}')
        self.assertEqual(check['env']['ENVIRONMENT_YAML_APPLY_ENABLED'], '${{ vars.ENVIRONMENT_YAML_APPLY_ENABLED }}')
        self.assertEqual(jobs['approval_preflight']['environment'], 'dev-demo-apply')
        self.assertIn('--confirm-environment "$CONFIRM_ENVIRONMENT"', check['run'])
        self.assertEqual(check['env']['CONFIRM_ENVIRONMENT'], '${{ inputs.confirm_environment }}')
        self.assertEqual(definition['on']['workflow_dispatch']['inputs']['confirm_environment']['default'], '')
        self.assertIn("needs.approval_preflight.result == 'success'", jobs['infra']['if'])
        self.assertIn("needs.approval_preflight.result == 'skipped'", jobs['infra']['if'])
        self.assertNotIn("needs.approval_preflight.result == 'failure'", jobs['infra']['if'])
        for job in ('infra', 'account', 'workspace_access'):
            self.assertEqual(jobs[job]['with']['confirm_environment'], '${{ inputs.confirm_environment }}')
            # An ancestor preflight skips for plan-only and other targets. Explicit
            # status functions prevent GitHub from silently skipping later jobs.
            self.assertIn('!cancelled()', jobs[job]['if'])
        self.assertIn("needs.infra.result == 'success'", jobs['account']['if'])
        self.assertIn("needs.account.result == 'success'", jobs['workspace_access']['if'])

    def test_root_demo_actions_require_manual_main_and_forward_confirmation(self):
        jobs = workflow('environment-root.yml')['jobs']
        for job in jobs.values():
            self.assertIn("github.ref == 'refs/heads/main'", job['if'])
            self.assertIn("github.event_name == 'workflow_dispatch'", job['if'])
        apply = next(step for step in jobs['apply']['steps'] if step.get('name') == 'Apply exact saved plan')
        self.assertIn('--confirm-environment "$CONFIRM_ENVIRONMENT"', apply['run'])
        self.assertEqual(apply['env']['CONFIRM_ENVIRONMENT'], '${{ inputs.confirm_environment }}')
        self.assertEqual(apply['env']['GH_TOKEN'], '${{ github.token }}')

    def test_feature_job_follows_account_and_is_scoped_to_trusted_demo(self):
        provision = workflow('environment-provision.yml')
        job = provision['jobs']['workspace_access']
        self.assertEqual(job['needs'], 'account')
        self.assertEqual(job['uses'], './.github/workflows/environment-workspace-access.yml')
        for condition in ("github.ref == 'refs/heads/main'", "inputs.target_environment == 'dev'",
                          "inputs.target_workspace == 'demo'"):
            self.assertIn(condition, job['if'])
        self.assertEqual(job['with']['deploy'], '${{ inputs.deploy }}')
        self.assertEqual(provision['permissions']['actions'], 'read')

    def test_retirement_precedes_account_and_infrastructure(self):
        jobs = workflow('environment-deprovision.yml')['jobs']
        self.assertEqual(jobs['workspace_access']['with']['retire'], 'true')
        self.assertEqual(jobs['workspace_access']['with']['deploy'], '${{ inputs.execute_destroy }}')
        self.assertEqual(jobs['account']['needs'], 'workspace_access')
        self.assertIn("needs.workspace_access.result == 'success'", jobs['account']['if'])
        self.assertIn("needs.workspace_access.result == 'skipped'", jobs['account']['if'])
        self.assertNotIn("needs.workspace_access.result == 'failure'", jobs['account']['if'])
        self.assertEqual(jobs['infra']['needs'], 'account')
        self.assertIn('!cancelled()', jobs['infra']['if'])
        self.assertIn("needs.account.result == 'success'", jobs['infra']['if'])
        for condition in ("github.ref == 'refs/heads/main'", "github.event_name == 'workflow_dispatch'"):
            self.assertIn(condition, jobs['account']['if'])

    def test_demo_destroy_root_requires_manual_main_and_trusted_admin_token(self):
        jobs = workflow('environment-destroy-root.yml')['jobs']
        for job in jobs.values():
            self.assertIn("github.ref == 'refs/heads/main'", job['if'])
            self.assertIn("github.event_name == 'workflow_dispatch'", job['if'])
        self.assertEqual(jobs['destroy']['env']['GH_TOKEN'], '${{ github.token }}')
        self.assertEqual(jobs['destroy']['env']['ENVIRONMENT_YAML_DESTROY_ENABLED'],
                         '${{ vars.ENVIRONMENT_YAML_DESTROY_ENABLED }}')

    def test_feature_workflow_saves_exact_plan_and_never_uploads_state(self):
        definition = workflow('environment-workspace-access.yml')
        jobs = definition['jobs']
        self.assertIn("github.ref == 'refs/heads/main'", jobs['plan']['if'])
        self.assertIn('inputs.deploy', jobs['apply']['if'])
        self.assertEqual(jobs['apply']['needs'], 'plan')
        self.assertEqual(jobs['apply']['environment'], 'dev-demo-apply')
        self.assertEqual(definition['on']['workflow_call']['inputs']['retire']['default'], 'false')
        upload = next(step for step in jobs['plan']['steps'] if 'upload-artifact' in step.get('uses', ''))
        paths = upload['with']['path'].splitlines()
        self.assertEqual(len(paths), 2)
        self.assertTrue(paths[0].endswith('/terraform.tfplan'))
        self.assertTrue(paths[1].endswith('/manifest.json'))
        self.assertNotIn('.tfstate', upload['with']['path'])
        self.assertEqual(upload['with']['retention-days'], '1')

    def test_storage_purge_is_explicit_and_passed_through_both_root_previews(self):
        definition = workflow('environment-deprovision.yml')
        inputs = definition['on']['workflow_dispatch']['inputs']
        self.assertEqual(inputs['purge_storage']['default'], 'false')
        self.assertEqual(inputs['confirm_purge_storage']['default'], '')
        for name in ('account', 'infra'):
            job = definition['jobs'][name]
            self.assertEqual(job['with']['purge_storage'], '${{ inputs.purge_storage }}')
            self.assertEqual(job['with']['confirm_purge_storage'], '${{ inputs.confirm_purge_storage }}')
        root = workflow('environment-destroy-root.yml')
        self.assertEqual(root['jobs']['destroy']['needs'], 'preview')
        for job in root['jobs'].values():
            self.assertEqual(job['env']['PURGE_STORAGE'], '${{ inputs.purge_storage }}')
            commands = '\n'.join(step.get('run', '') for step in job['steps'])
            self.assertIn('--purge-storage --confirm-purge-storage "$CONFIRM_PURGE_STORAGE"', commands)
            self.assertIn('"${storage_args[@]}"', commands)
            self.assertIn('requirements-storage.txt', commands)
