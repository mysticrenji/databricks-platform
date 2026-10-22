"""Expand validated intent; this is not a live Databricks plan."""
from collections import defaultdict


def compile_policy(policy):
    def fixed(value):
        return {'type': 'fixed', 'value': value}

    definition = {
        'spark_version': {'type': 'allowlist', 'values': sorted(policy['runtime']['allowed_versions']),
                          'defaultValue': policy['runtime']['default_version']},
        'use_ml_runtime': fixed(all('-cpu-ml-' in version for version in policy['runtime']['allowed_versions'])),
        'data_security_mode': fixed(policy['data_security_mode']),
        'autotermination_minutes': fixed(policy['autotermination_minutes']),
        'autoscale.min_workers': fixed(policy['autoscaling']['min_workers']),
        'autoscale.max_workers': {'type': 'range', 'minValue': policy['autoscaling']['min_workers'],
                                 'maxValue': policy['autoscaling']['max_workers'],
                                 'defaultValue': policy['autoscaling']['max_workers']},
        'num_workers': {'type': 'forbidden'},
        'is_single_node': fixed(False),
        'spark_conf.spark.databricks.cluster.profile': {'type': 'forbidden'},
        'instance_pool_id': {'type': 'forbidden'},
        'driver_instance_pool_id': {'type': 'forbidden'},
        'aws_attributes.instance_profile_arn': {'type': 'forbidden'},
        'docker_image.url': {'type': 'forbidden'},
        'worker_node_type_flexibility.alternate_node_type_ids': fixed(''),
        'driver_node_type_flexibility.alternate_node_type_ids': fixed(''),
    }
    for field, attribute in [('worker_nodes', 'node_type_id'), ('driver_nodes', 'driver_node_type_id')]:
        definition[attribute] = {'type': 'allowlist', 'values': sorted(policy[field]['allowed_types']),
                                 'defaultValue': policy[field]['default_type']}
    for variant in ('workspace', 'volumes', 's3', 'file'):
        definition[f'init_scripts.*.{variant}.destination'] = {'type': 'forbidden'}
    definition['init_scripts.*.s3.region'] = {'type': 'forbidden'}
    return {'description': policy['description'], 'max_clusters_per_user': policy['max_clusters_per_user'],
            'definition': definition}


def preview(bundle):
    groups = bundle['principals']['groups']
    roles = bundle['roles']
    assignments = {}
    policy_acls, warehouse_acls = defaultdict(dict), defaultdict(dict)
    for key, group in sorted(groups.items()):
        persona = roles['personas'][group['persona']]
        name = group['display_name']
        assignments[key] = {**group, 'workspace_role': persona['workspace_role'],
                            'workspace_access_owner': '02-account' if group['lifecycle'] == 'terraform' else '05-permissions',
                            'entitlements': persona['entitlements']}
        for policy in persona['cluster_policies']:
            policy_acls[policy][name] = 'CAN_USE'
        for warehouse, level in persona['sql_warehouses'].items():
            warehouse_acls[warehouse][name] = level

    privileges, sources = defaultdict(set), defaultdict(set)

    def contribute(principal, kind, name, grants, source):
        key = (principal, kind, name)
        privileges[key].update(grants)
        sources[key].add(source)

    warnings = {
        'OFFLINE PREVIEW ONLY: no API reads, live comparison, revocations or executable plan.',
        'Runtime/node availability, data object existence and effective access are not verified.',
        'Workspace ADMIN and other memberships may provide access beyond these declarations.',
        'Warehouse creation can provision billable compute; policy creation starts no clusters.',
        'Offline preview does not verify Terraform ownership or CI approval protection.',
        'Bootstrap groups/assignments belong to root02; entitlements and compute use separate Terraform states.',
    }
    for request in bundle['workloads']:
        group = bundle['resources']['workloads'][request['workload']]['principal']
        for grant in request['data_access']:
            kind = 'table' if 'table' in grant else 'schema' if 'schema' in grant else 'catalog'
            principal = groups[group]['display_name']
            source = f'{request["workload"]}/{grant["id"]}'
            parts = [grant['catalog']]
            if kind in ('schema', 'table'):
                parts.append(grant['schema'])
            if kind == 'table':
                parts.append(grant['table'])
            name = '.'.join(parts)
            expanded = roles['packages'][grant['access']][kind]
            contribute(principal, kind, name, expanded, source)
            if kind != 'catalog':
                contribute(principal, 'catalog', grant['catalog'], ['USE_CATALOG'], source)
                contribute(principal, 'schema', '.'.join(parts[:2]), ['USE_SCHEMA'], source)
            if kind == 'schema' and 'SELECT' in expanded:
                warnings.add(f'{principal}: SELECT on schema {name} includes current and future tables/views.')

    target = bundle['target']
    if not target['active']:
        warnings.add('Target is inactive: verify identities/reviewers before enabling live planning.')
    return {
        'kind': 'offline-desired-state', 'version': 1, 'executable': False,
        'target': target, 'groups': assignments,
        'grants': [
            {'principal': principal, 'object_type': kind, 'object_name': name,
             'privileges': sorted(privileges[(principal, kind, name)]),
             'sources': sorted(sources[(principal, kind, name)])}
            for principal, kind, name in sorted(privileges)
        ],
        'cluster_policies': {
            name: {**compile_policy(policy), 'permissions': policy_acls[name]}
            for name, policy in sorted(bundle['compute']['cluster_policies'].items())
        },
        'sql_warehouses': {
            name: {**warehouse, 'permissions': warehouse_acls[name]}
            for name, warehouse in sorted(bundle['compute']['sql_warehouses'].items())
        },
        'warnings': sorted(warnings),
    }
