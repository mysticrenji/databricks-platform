"""Storage cleanup contracts; all S3 operations use an in-memory fake."""
import copy
import unittest
from types import SimpleNamespace

import test_environment
import storage_cleanup as cleanup
from environment import ConfigError


class S3Error(Exception):
    def __init__(self, code):
        self.response = {'Error': {'Code': code}}


class FakeS3:
    def __init__(self):
        self.exists = True
        self.region = 'eu-central-1'
        self.versions = [{'Key': 'data', 'VersionId': str(i), 'Size': 1} for i in range(1001)]
        self.markers = [{'Key': 'data', 'VersionId': 'marker'}]
        self.uploads = [{'Key': 'pending', 'UploadId': 'upload'}]
        self.writes = []
        self.errors = []

    def head_bucket(self, **kwargs):
        if not self.exists:
            raise S3Error('404')
        return {'BucketRegion': self.region}

    def get_bucket_location(self, **kwargs):
        return {'LocationConstraint': self.region}

    def get_paginator(self, operation):
        def paginate(**kwargs):
            if operation == 'list_object_versions':
                yield {'Versions': copy.deepcopy(self.versions[:1000])}
                yield {'Versions': copy.deepcopy(self.versions[1000:]), 'DeleteMarkers': copy.deepcopy(self.markers)}
            else:
                yield {'Uploads': copy.deepcopy(self.uploads)}
        return SimpleNamespace(paginate=paginate)

    def delete_objects(self, **kwargs):
        self.writes.append(('objects', kwargs))
        if not self.errors:
            ids = {v['VersionId'] for v in kwargs['Delete']['Objects']}
            self.versions = [v for v in self.versions if v['VersionId'] not in ids]
            self.markers = [v for v in self.markers if v['VersionId'] not in ids]
        return {'Errors': self.errors}

    def abort_multipart_upload(self, **kwargs):
        self.writes.append(('upload', kwargs))
        self.uploads = []

    def delete_bucket(self, **kwargs):
        self.writes.append(('bucket', kwargs))
        if self.versions or self.markers or self.uploads:
            raise S3Error('BucketNotEmpty')
        self.exists = False


class StorageCleanupTests(unittest.TestCase):
    def setUp(self):
        self.s3 = FakeS3()
        self.buckets = [{'address': 'module.data_storage.aws_s3_bucket.this["landing"]',
                         'name': 'databricks-dev-shared-landing-123456789012'}]
        self.account = '123456789012'

    def test_preview_inventory_is_paginated_read_only_and_reports_data(self):
        result = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        self.assertEqual(result[0]['versions'], 1001)
        self.assertEqual(result[0]['delete_markers'], 1)
        self.assertEqual(result[0]['bytes'], 1001)
        self.assertEqual(result[0]['multipart_uploads'], 1)
        self.assertEqual(self.s3.writes, [])

    def test_purge_removes_all_versions_markers_uploads_and_verifies_absence(self):
        reviewed = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', reviewed)
        self.assertFalse(self.s3.exists)
        batches = [call['Delete']['Objects'] for kind, call in self.s3.writes if kind == 'objects']
        self.assertEqual([len(batch) for batch in batches], [1000, 2])
        self.assertEqual([kind for kind, _ in self.s3.writes][-2:], ['upload', 'bucket'])
        for _, call in self.s3.writes:
            self.assertEqual(call['ExpectedBucketOwner'], self.account)

    def test_object_delete_errors_stop_before_bucket_delete(self):
        self.s3.errors = [{'Code': 'AccessDenied', 'Key': 'data'}]
        reviewed = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        with self.assertRaisesRegex(ConfigError, 'AccessDenied'):
            cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', reviewed)
        self.assertFalse(any(kind == 'bucket' for kind, _ in self.s3.writes))

    def test_wrong_region_or_unreadable_bucket_prevents_all_deletion(self):
        self.s3.region = 'eu-west-1'
        with self.assertRaisesRegex(ConfigError, 'region'):
            cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', [])
        self.assertEqual(self.s3.writes, [])
        self.s3.head_bucket = lambda **kwargs: (_ for _ in ()).throw(S3Error('403'))
        with self.assertRaisesRegex(ConfigError, '403'):
            cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', [])
        self.assertEqual(self.s3.writes, [])

    def test_absent_bucket_is_idempotent_but_unverified_deletion_fails(self):
        self.s3.exists = False
        reviewed = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', reviewed)
        self.assertEqual(self.s3.writes, [])
        self.s3.exists = True
        self.s3.delete_bucket = lambda **kwargs: None
        reviewed = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        with self.assertRaisesRegex(ConfigError, 'still exists'):
            cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', reviewed)

    def test_late_unreviewed_writes_are_never_deleted(self):
        reviewed = cleanup.inspect(self.s3, self.buckets, self.account, 'eu-central-1')
        self.s3.versions.append({'Key': 'unreviewed', 'VersionId': 'late', 'Size': 12})
        with self.assertRaisesRegex(ConfigError, 'changed'):
            cleanup.purge(self.s3, self.buckets, self.account, 'eu-central-1', reviewed)
        self.assertEqual(self.s3.writes, [])

    def test_inventory_uses_only_state_owned_expected_buckets_and_excludes_backend(self):
        fixture = test_environment.EnvironmentTests()
        fixture.setUp()
        config = fixture.config
        from environment import render
        values = render(config)['01-infra']
        state = {'resources': [{'mode': 'managed', 'module': 'module.data_storage',
                 'type': 'aws_s3_bucket', 'name': 'this', 'instances': [
                     {'index_key': 'landing', 'attributes': {'id': self.buckets[0]['name']}}]}]}
        with self.assertRaisesRegex(ConfigError, 'incomplete'):
            cleanup.bucket_inventory(state, config, values, 'state')
        state['resources'][0]['instances'].append({'index_key': 'uc_managed', 'attributes': {
            'id': 'databricks-dev-shared-uc-managed-123456789012'}})
        state['resources'].append({'mode': 'managed', 'module': 'module.root_storage',
            'type': 'aws_s3_bucket', 'name': 'root', 'instances': [
                {'attributes': {'id': values['root_storage_bucket_name']}}]})
        self.assertEqual(cleanup.bucket_inventory(state, config, values, 'state')[0], self.buckets[0])
        with self.assertRaisesRegex(ConfigError, 'state bucket'):
            cleanup.bucket_inventory(state, config, values, self.buckets[0]['name'])
        state['resources'][0]['instances'][0]['attributes']['id'] = 'another-workspace'
        with self.assertRaisesRegex(ConfigError, 'configured'):
            cleanup.bucket_inventory(state, config, values, 'state')
