import copy
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configuration import ConfigError, FOUNDATION, load_workspace_access


class WorkspaceMatrixTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(FOUNDATION / 'platform', self.root / 'platform')

    def test_matrix_loads_without_dataset_compute_or_target_files(self):
        for folder in ('resources', 'targets'):
            shutil.rmtree(self.root / 'platform/access' / folder)
        shutil.rmtree(self.root / 'platform/compute')
        (self.root / 'platform/access/reviewers.yaml').unlink()
        result = load_workspace_access(self.root)
        matrix = {name: persona['entitlements'] for name, persona in result['roles']['personas'].items()}
        self.assertEqual(matrix['analysts'], {
            'workspace_access': False, 'databricks_sql_access': True,
            'allow_cluster_create': False, 'allow_instance_pool_create': False})
        self.assertTrue(all(matrix['admins'].values()))
        for key in ('engineers', 'ml'):
            self.assertEqual(matrix[key], matrix['analysts'] | {'workspace_access': True})

    def test_non_admin_creation_and_admin_capability_removal_fail(self):
        path = self.root / 'platform/access/roles.yaml'
        original = yaml.safe_load(path.read_text())
        for persona, field, value in [('engineers', 'allow_cluster_create', True),
                                      ('analysts', 'allow_instance_pool_create', True),
                                      ('admins', 'workspace_access', False),
                                      ('admins', 'allow_cluster_create', False),
                                      ('admins', 'databricks_sql_access', False)]:
            with self.subTest(persona=persona, field=field):
                document = copy.deepcopy(original)
                document['personas'][persona]['entitlements'][field] = value
                path.write_text(yaml.safe_dump(document))
                with self.assertRaises(ConfigError):
                    load_workspace_access(self.root)

    def test_only_terraform_bootstrap_and_matching_provisioning_identity(self):
        path = self.root / 'platform/access/principals/dev/demo.yaml'
        original = yaml.safe_load(path.read_text())
        document = copy.deepcopy(original)
        document['groups']['ml']['lifecycle'] = 'create'
        path.write_text(yaml.safe_dump(document))
        with self.assertRaisesRegex(ConfigError, 'Terraform-owned'):
            load_workspace_access(self.root)
        path.write_text(yaml.safe_dump(original))
        config = self.root / 'platform/environments/dev/demo.yaml'
        document = yaml.safe_load(config.read_text())
        document['workspace']['name'] = 'other'
        config.write_text(yaml.safe_dump(document))
        with self.assertRaisesRegex(ConfigError, 'match dev/demo'):
            load_workspace_access(self.root)

    def test_other_targets_stay_disabled(self):
        for environment, workspace in [('staging', 'demo'), ('production', 'demo'), ('dev', 'shared')]:
            with self.assertRaisesRegex(ConfigError, 'dev/demo only'):
                load_workspace_access(self.root, environment, workspace)
