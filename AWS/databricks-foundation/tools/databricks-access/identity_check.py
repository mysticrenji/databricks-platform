#!/usr/bin/env python3
"""Dev/demo live CI diagnostics: identity and optional metastore discovery, reads only."""
import argparse
import os
import re
import sys
from uuid import UUID

from configuration import load_bundle


class IdentityCheckError(ValueError):
    """Safe diagnostic written by this check, without SDK configuration details."""


def verify_identity(account, workspace, account_id, workspace_id, workspace_url):
    record = account.workspaces.get(workspace_id=int(workspace_id))
    status = getattr(record.workspace_status, 'value', record.workspace_status)
    if (record.account_id != account_id or str(record.workspace_id) != workspace_id
            or workspace_url != f'https://{record.deployment_name}.cloud.databricks.com'):
        raise IdentityCheckError('Account workspace identity does not match the provisioning outputs')
    if status != 'RUNNING':
        raise IdentityCheckError('Expected workspace is not RUNNING')
    if not workspace.current_user.me().id:
        raise IdentityCheckError('Workspace returned no authenticated identity')
    return ['Account workspace identity: PASS', 'Workspace OAuth access: PASS']


def verify_metastore(workspace, workspace_id):
    try:
        assignment = workspace.metastores.current()
    except Exception as exc:
        raise IdentityCheckError(f'Metastore assignment read failed ({type(exc).__name__})') from None
    if str(assignment.workspace_id) != workspace_id:
        raise IdentityCheckError('Metastore assignment belongs to a different workspace')
    try:
        metastore_id = UUID(assignment.metastore_id)
        if metastore_id.int == 0:
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise IdentityCheckError('Workspace has no valid metastore assignment') from None
    try:
        summary = workspace.metastores.summary()
    except Exception as exc:
        raise IdentityCheckError(f'Metastore summary read failed ({type(exc).__name__})') from None
    if summary.metastore_id != assignment.metastore_id:
        raise IdentityCheckError('Metastore summary does not match the workspace assignment')
    return [f'Observed metastore ID: {metastore_id}',
            'Workspace metastore assignment: PASS', 'Metastore summary visibility: PASS']


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace-id', required=True)
    parser.add_argument('--workspace-url', required=True)
    parser.add_argument('--check-metastore', action='store_true',
                        help='Discover assignment and verify summary visibility after identity checks')
    args = parser.parse_args(argv)
    try:
        bundle = load_bundle(environment='dev', workspace='demo')
        account_id = bundle['target']['account_id']
        if os.environ.get('DATABRICKS_ACCOUNT_ID') != account_id:
            raise IdentityCheckError('CI account ID must match dev/demo configuration')
        if not re.fullmatch(r'[1-9][0-9]*', args.workspace_id):
            raise IdentityCheckError('A real provisioning workspace ID is required')
        if not re.fullmatch(r'https://[a-z0-9-]+\.cloud\.databricks\.com', args.workspace_url):
            raise IdentityCheckError('A canonical AWS Databricks workspace URL is required')
        for key in ('DATABRICKS_CLIENT_ID', 'DATABRICKS_CLIENT_SECRET'):
            if not os.environ.get(key):
                raise IdentityCheckError(f'Missing {key}')
        from databricks.sdk import AccountClient, WorkspaceClient
        credentials = dict(client_id=os.environ['DATABRICKS_CLIENT_ID'],
                           client_secret=os.environ['DATABRICKS_CLIENT_SECRET'],
                           auth_type='oauth-m2m')
        account = AccountClient(host='https://accounts.cloud.databricks.com',
                                account_id=account_id, **credentials)
        workspace = WorkspaceClient(host=args.workspace_url, **credentials)
        for line in verify_identity(account, workspace, account_id,
                                    args.workspace_id, args.workspace_url):
            print(line)
        if args.check_metastore:
            for line in verify_metastore(workspace, args.workspace_id):
                print(line)
            print('Metastore discovery only; approved target binding, grants and compute readiness are not verified.')
        else:
            print('Identity check only; metastore, grants and compute readiness are not yet verified.')
    except Exception as exc:
        # SDK authentication errors can contain configuration details. Never print them.
        message = str(exc) if isinstance(exc, IdentityCheckError) else type(exc).__name__
        print(f'Live identity check failed: {message}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
