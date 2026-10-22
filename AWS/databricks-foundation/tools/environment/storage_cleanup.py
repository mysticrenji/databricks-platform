"""Explicit S3 purge of reviewed, state-owned workspace buckets; never KMS."""
import hashlib
import json

from environment import ConfigError


def client(region):
    # Offline validation and retention-only runs do not need the SDK.
    import boto3
    return boto3.client('s3', region_name=region)


def bucket_inventory(state, config, values, state_bucket):
    account = config['environment']['aws_account_id']
    prefix = f'databricks-{config["environment"]["name"]}-{config["workspace"]["name"]}'
    expected = {
        'module.root_storage.aws_s3_bucket.root': values['root_storage_bucket_name'],
        'module.data_storage.aws_s3_bucket.this["landing"]': f'{prefix}-landing-{account}',
        'module.data_storage.aws_s3_bucket.this["uc_managed"]': f'{prefix}-uc-managed-{account}',
    }
    if values.get('enable_observability_bucket'):
        expected['module.data_storage.aws_s3_bucket.this["observability"]'] = (
            values.get('observability_bucket_name') or f'{prefix}-logs-{account}')
    buckets = []
    for resource in (state or {}).get('resources', []):
        if resource['mode'] != 'managed' or resource['type'] != 'aws_s3_bucket':
            continue
        for instance in resource.get('instances', []):
            address = '.'.join(filter(None, (resource.get('module'), resource['type'], resource['name'])))
            if 'index_key' in instance:
                address += f'[{json.dumps(instance["index_key"])}]'
            name = instance['attributes']['id']
            if name == state_bucket:
                raise ConfigError('Storage purge must never include the Terraform state bucket')
            if expected.get(address) != name or instance.get('deposed'):
                raise ConfigError(f'{address}: bucket is not the configured workspace storage; review ownership')
            buckets.append({'address': address, 'name': name})
    if len({b['name'] for b in buckets}) != len(buckets):
        raise ConfigError('Duplicate bucket ownership in purge inventory')
    if {bucket['address'] for bucket in buckets} != set(expected):
        raise ConfigError('Workspace bucket inventory is incomplete; recover missing ownership from the previous state backup before purge')
    return sorted(buckets, key=lambda b: b['address'])


def error_code(exc):
    return str(getattr(exc, 'response', {}).get('Error', {}).get('Code', ''))


def exists(s3, binding):
    try:
        s3.head_bucket(**binding)
        return True
    except Exception as exc:
        if error_code(exc) in ('404', 'NoSuchBucket'):
            return False
        raise ConfigError(f'Cannot verify bucket {binding["Bucket"]}: {exc} {error_code(exc)}') from exc


def contents(s3, binding):
    versions, markers, uploads = [], [], []
    for page in s3.get_paginator('list_object_versions').paginate(**binding):
        versions.extend({'Key': v['Key'], 'VersionId': v['VersionId'], 'Size': v['Size'], 'ETag': v.get('ETag')}
                        for v in page.get('Versions', []))
        markers.extend({'Key': v['Key'], 'VersionId': v['VersionId']}
                       for v in page.get('DeleteMarkers', []))
    for page in s3.get_paginator('list_multipart_uploads').paginate(**binding):
        uploads.extend({'Key': u['Key'], 'UploadId': u['UploadId']} for u in page.get('Uploads', []))
    return [sorted(items, key=lambda item: json.dumps(item, sort_keys=True))
            for items in (versions, markers, uploads)]


def snapshots(s3, buckets, account, region):
    result = []
    try:
        for bucket in buckets:
            binding = {'Bucket': bucket['name'], 'ExpectedBucketOwner': account}
            present = exists(s3, binding)
            versions, markers, uploads = [], [], []
            if present:
                location = s3.get_bucket_location(**binding).get('LocationConstraint') or 'us-east-1'
                if location != region:
                    raise ConfigError(f'{bucket["name"]}: bucket region does not match configured region')
                versions, markers, uploads = contents(s3, binding)
            summary = bucket | {
                'exists': present, 'versions': len(versions), 'delete_markers': len(markers),
                'bytes': sum(v['Size'] for v in versions), 'multipart_uploads': len(uploads),
                'contents_sha256': hashlib.sha256(json.dumps([versions, markers, uploads], sort_keys=True).encode()).hexdigest(),
            }
            result.append((summary, versions, markers, uploads))
    except ConfigError:
        raise
    except Exception as exc:
        raise ConfigError(f'Cannot inventory workspace storage: {exc}') from exc
    return result


def inspect(s3, buckets, account, region):
    return [summary for summary, *_ in snapshots(s3, buckets, account, region)]


def purge(s3, buckets, account, region, reviewed):
    # Validate all snapshots before mutation, then delete exactly these version IDs.
    current = snapshots(s3, buckets, account, region)
    if [summary for summary, *_ in current] != reviewed:
        raise ConfigError('Storage contents changed after review; storage purge refused')
    try:
        for bucket, versions, markers, uploads in current:
            if not bucket['exists']:
                continue
            binding = {'Bucket': bucket['name'], 'ExpectedBucketOwner': account}
            objects = [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in versions + markers]
            for start in range(0, len(objects), 1000):
                response = s3.delete_objects(**binding, Delete={'Objects': objects[start:start + 1000], 'Quiet': True})
                if response.get('Errors'):
                    raise ConfigError(f'{bucket["name"]}: object deletion failed: {response["Errors"]}')
            for upload in uploads:
                s3.abort_multipart_upload(**binding, **upload)
            s3.delete_bucket(**binding)
            if exists(s3, binding):
                raise ConfigError(f'{bucket["name"]}: bucket still exists after deletion')
            print(f'Purged and verified absent: {bucket["name"]}', flush=True)
    except ConfigError:
        raise
    except Exception as exc:
        raise ConfigError(f'Storage purge incomplete; retain the preview inventory for recovery: {exc}') from exc
