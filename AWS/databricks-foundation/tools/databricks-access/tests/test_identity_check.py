from contextlib import redirect_stderr, redirect_stdout
import io
import os
import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from identity_check import main, verify_identity, verify_metastore


class IdentityCheckTests(unittest.TestCase):
    def setUp(self):
        self.account = Mock()
        self.workspace = Mock()
        self.account.workspaces.get.return_value = SimpleNamespace(
            account_id='account', workspace_id=123,
            deployment_name='dbc-example', workspace_status='RUNNING')
        self.workspace.current_user.me.return_value = SimpleNamespace(id='456')

    def check(self):
        return verify_identity(self.account, self.workspace, 'account', '123',
                               'https://dbc-example.cloud.databricks.com')

    def test_account_and_workspace_reads_succeed(self):
        self.assertEqual(self.check(), ['Account workspace identity: PASS',
                                       'Workspace OAuth access: PASS'])

    def test_mismatch_or_unready_target_stops_before_workspace_auth(self):
        for field, value in [('account_id', 'other'), ('workspace_id', 999),
                             ('deployment_name', 'other'), ('workspace_status', 'PROVISIONING')]:
            with self.subTest(field=field):
                record = self.account.workspaces.get.return_value
                original = getattr(record, field)
                setattr(record, field, value)
                with self.assertRaises(ValueError):
                    self.check()
                self.workspace.current_user.me.assert_not_called()
                setattr(record, field, original)

    def test_failed_reads_are_not_success(self):
        self.account.workspaces.get.side_effect = PermissionError('forbidden')
        with self.assertRaises(PermissionError):
            self.check()
        self.workspace.current_user.me.assert_not_called()
        self.account.workspaces.get.side_effect = None
        self.workspace.current_user.me.side_effect = PermissionError('forbidden')
        with self.assertRaises(PermissionError):
            self.check()

    def test_missing_authenticated_identity_fails(self):
        self.workspace.current_user.me.return_value = SimpleNamespace(id=None)
        with self.assertRaises(ValueError):
            self.check()


class IdentityCommandTests(unittest.TestCase):
    def run_check(self, *args):
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            result = main(args)
        return result, output.getvalue()

    def test_invalid_inputs_stop_before_sdk_authentication(self):
        sdk = SimpleNamespace(AccountClient=Mock())
        with patch.dict(os.environ, {}, clear=True), patch.dict(sys.modules, {'databricks.sdk': sdk}):
            code, output = self.run_check('--workspace-id', '123', '--workspace-url', 'https://example.com')
            self.assertEqual(code, 1)
            self.assertIn('CI account ID must match', output)
            sdk.AccountClient.assert_not_called()

    def test_sdk_configuration_errors_are_redacted(self):
        from configuration import load_bundle
        credentials = {'DATABRICKS_ACCOUNT_ID': load_bundle()['target']['account_id'],
                       'DATABRICKS_CLIENT_ID': 'test-client', 'DATABRICKS_CLIENT_SECRET': 'sensitive-value'}
        sdk = SimpleNamespace(AccountClient=Mock(side_effect=ValueError('secret: sensitive-value')),
                              WorkspaceClient=Mock())
        with patch.dict(os.environ, credentials, clear=True), patch.dict(sys.modules, {'databricks.sdk': sdk}):
            code, output = self.run_check('--workspace-id', '123',
                                          '--workspace-url', 'https://dbc-example.cloud.databricks.com')
        self.assertEqual(code, 1)
        self.assertIn('ValueError', output)
        self.assertNotIn('sensitive-value', output)


class MetastoreCheckTests(unittest.TestCase):
    def setUp(self):
        self.workspace = Mock()
        self.metastore_id = '11111111-2222-3333-4444-555555555555'
        self.workspace.metastores.current.return_value = SimpleNamespace(
            workspace_id=123, metastore_id=self.metastore_id)
        self.workspace.metastores.summary.return_value = SimpleNamespace(metastore_id=self.metastore_id)

    def test_assignment_and_summary_identify_same_metastore(self):
        self.assertEqual(verify_metastore(self.workspace, '123'), [
            f'Observed metastore ID: {self.metastore_id}',
            'Workspace metastore assignment: PASS', 'Metastore summary visibility: PASS'])

    def test_missing_metastore_fails_before_summary(self):
        for value in (None, '', '00000000-0000-0000-0000-000000000000', 'invalid'):
            with self.subTest(value=value):
                self.workspace.metastores.current.return_value.metastore_id = value
                with self.assertRaisesRegex(ValueError, 'no valid metastore'):
                    verify_metastore(self.workspace, '123')
                self.workspace.metastores.summary.assert_not_called()

    def test_wrong_workspace_assignment_fails(self):
        self.workspace.metastores.current.return_value.workspace_id = 999
        with self.assertRaisesRegex(ValueError, 'different workspace'):
            verify_metastore(self.workspace, '123')
        self.workspace.metastores.summary.assert_not_called()

    def test_changed_assignment_or_incomplete_summary_fails(self):
        for value in (None, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'):
            with self.subTest(value=value):
                self.workspace.metastores.summary.return_value.metastore_id = value
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    verify_metastore(self.workspace, '123')

    def test_read_failures_name_stage_without_exposing_sdk_details(self):
        for method, stage in [('current', 'assignment'), ('summary', 'summary')]:
            with self.subTest(method=method):
                api = getattr(self.workspace.metastores, method)
                api.side_effect = PermissionError('sensitive-value')
                with self.assertRaisesRegex(ValueError, f'Metastore {stage} read failed \\(PermissionError\\)') as error:
                    verify_metastore(self.workspace, '123')
                self.assertNotIn('sensitive-value', str(error.exception))
                api.side_effect = None
