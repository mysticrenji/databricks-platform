"""Strict, credential-free loading and authorization of the dev/demo example."""
import json
from pathlib import Path
import sys

import jsonschema
import yaml

HERE = Path(__file__).resolve().parent
FOUNDATION = HERE.parent.parent


class ConfigError(ValueError):
    pass


class StrictLoader(yaml.SafeLoader):
    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            raise ConfigError('YAML aliases are not supported')
        return super().compose_node(parent, index)


def mapping(loader, node):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node)
        if not isinstance(key, str):
            raise ConfigError('YAML keys must be strings')
        if key in result:
            raise ConfigError(f'Duplicate YAML key: {key}')
        result[key] = loader.construct_object(value_node)
    return result


StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)


def load_yaml(path):
    try:
        return yaml.load(Path(path).read_text(), Loader=StrictLoader)
    except (OSError, yaml.YAMLError, RecursionError) as exc:
        raise ConfigError(f'{path}: cannot read YAML: {exc}') from exc


def check_schema(document, kind, label):
    schema = json.loads((HERE / 'schema.json').read_text())
    validator = jsonschema.Draft202012Validator(
        {'$ref': f'#/$defs/{kind}', '$defs': schema['$defs']},
        format_checker=jsonschema.FormatChecker(),
    )
    errors = sorted(validator.iter_errors(document), key=lambda error: str(list(error.path)))
    if errors:
        error = errors[0]
        location = '.'.join(map(str, error.path)) or 'document'
        raise ConfigError(f'{label}:{location}: {error.message}')


def require(condition, message):
    if not condition:
        raise ConfigError(message)


def validate_persona_access(roles):
    for name, persona in roles['personas'].items():
        require((persona['workspace_role'] == 'ADMIN') == (name == 'admins'),
                'Only the admins persona may assign workspace ADMIN')
        features = persona['entitlements']
        if name == 'admins':
            require(all(features.get(field) is True for field in (
                'workspace_access', 'databricks_sql_access', 'allow_cluster_create', 'allow_instance_pool_create')),
                'Admins must retain workspace, SQL and administrative compute capabilities')
        else:
            require(features.get('allow_cluster_create') is False
                    and features.get('allow_instance_pool_create') is False,
                    f'Persona {name} must explicitly disable unrestricted compute/pool creation')
            require(features['workspace_access'] or features['databricks_sql_access'],
                    f'Persona {name} requires at least one feature access entitlement')


def load_workspace_access(foundation=FOUNDATION, environment='dev', workspace='demo'):
    """Load the bootstrap matrix independently of datasets, compute and metastore targets."""
    require((environment, workspace) == ('dev', 'demo'), 'Workspace access supports dev/demo only')
    platform = Path(foundation) / 'platform'
    bundle = {}
    for kind, relative in [('roles', 'access/roles.yaml'), ('principals', 'access/principals/dev/demo.yaml')]:
        path = platform / relative
        bundle[kind] = load_yaml(path)
        check_schema(bundle[kind], kind, str(path))
    validate_persona_access(bundle['roles'])
    groups = bundle['principals']['groups']
    require(all(group['lifecycle'] == 'terraform' and 'account_group_id' not in group
                for group in groups.values()), 'Workspace access requires Terraform-owned root 02 groups')
    require(len({group['display_name'] for group in groups.values()}) == len(groups), 'Duplicate group display name')
    validate_workspace_access(bundle, platform)
    if str(HERE.parent / 'environment') not in sys.path:
        sys.path.insert(0, str(HERE.parent / 'environment'))
    from environment import ConfigError as ProvisioningError, validate
    try:
        config = validate(load_yaml(platform / 'environments/dev/demo.yaml'))
    except ProvisioningError as exc:
        raise ConfigError(str(exc)) from exc
    require(config['environment']['name'] == environment and config['workspace']['name'] == workspace,
            'Provisioning configuration must match dev/demo')
    bundle['provisioning'] = config
    return bundle


def load_bundle(foundation=FOUNDATION, environment='dev', workspace='demo'):
    require((environment, workspace) == ('dev', 'demo'),
            'This first implementation supports dev/demo only')
    platform = Path(foundation) / 'platform'
    paths = {
        'roles': platform / 'access/roles.yaml',
        'principals': platform / 'access/principals/dev/demo.yaml',
        'resources': platform / 'access/resources/dev/demo.yaml',
        'reviewers': platform / 'access/reviewers.yaml',
        'target': platform / 'access/targets/dev/demo.yaml',
        'compute': platform / 'compute/dev.yaml',
    }
    bundle = {}
    for kind, path in paths.items():
        bundle[kind] = load_yaml(path)
        check_schema(bundle[kind], kind, str(path))
    legacy = Path(foundation) / 'config/access'
    require(not legacy.exists() or not any(legacy.rglob('*.*')),
            'Legacy config/access files are unsupported; move declarations to foundation workloads/')
    workloads_directory = Path(foundation) / 'workloads'
    require(workloads_directory.is_dir(), f'Missing workloads directory: {workloads_directory}')
    bundle['workloads'] = []
    for directory in sorted(workloads_directory.iterdir()):
        if directory.name == 'README.md':
            continue
        require(directory.is_dir() and not directory.is_symlink(),
                'Workloads directory must contain workload folders and README.md only')
        require(directory.name in bundle['resources']['workloads'],
                f'Unknown workload folder: {directory.name}')
        entries = sorted(directory.iterdir())
        require(all(path.is_file() and not path.is_symlink() and path.name == 'dev-demo.yaml' for path in entries),
                f'{directory}: this first slice supports dev-demo.yaml only')
        if not entries:
            continue
        path = directory / 'dev-demo.yaml'
        request = load_yaml(path)
        check_schema(request, 'workload', str(path))
        bundle['workloads'].append({**request, 'workload': directory.name})
    provisioning = load_yaml(platform / 'environments/dev/demo.yaml')
    require(isinstance(provisioning, dict), 'Provisioning configuration must be a mapping')
    require(all(isinstance(provisioning.get(key), dict) for key in ('environment', 'workspace', 'databricks')),
            'Provisioning environment/workspace/databricks must be mappings')
    require(provisioning['environment'].get('name') == environment
            and provisioning['workspace'].get('name') == workspace,
            'Provisioning configuration must match dev/demo')
    require(provisioning['databricks'].get('account_id') == bundle['target']['account_id'],
            'Target account_id must match environment provisioning configuration')
    validate_bundle(bundle)
    validate_workspace_access(bundle, platform)
    return bundle


def validate_workspace_access(bundle, platform):
    """Terraform owns bootstrap groups/assignments; access intent may only refer to them."""
    path = platform / 'terraform-inputs/dev/demo.02-account.json'
    try:
        values = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise ConfigError(f'Terraform workspace access: cannot read {path}') from exc
    require(isinstance(values, dict), 'Terraform workspace access inputs must be an object')
    groups = values.get('account_groups', {})
    require(isinstance(groups, dict), 'Terraform workspace access groups must be an object')
    for key, group in bundle['principals']['groups'].items():
        name = group['display_name']
        if group['lifecycle'] != 'terraform':
            require(name not in groups, f'Group {key} is already Terraform-owned; use lifecycle: terraform')
            continue
        expected_role = bundle['roles']['personas'][group['persona']]['workspace_role']
        configured = groups.get(name)
        require(isinstance(configured, dict)
                and configured.get('workspace_permission', 'USER') == expected_role
                and configured.get('member_ids', {}) == {}
                and not configured.get('manager_group_names'),
                f'Terraform workspace access for {key} must exist with role {expected_role}, '
                'external membership and no group-manager delegation')


def validate_compute(compute):
    """Validate compute constraints without requiring any data-object declarations."""
    for name, policy in compute['cluster_policies'].items():
        for field, allowed, default in (
            ('runtime', 'allowed_versions', 'default_version'),
            ('worker_nodes', 'allowed_types', 'default_type'),
            ('driver_nodes', 'allowed_types', 'default_type'),
        ):
            require(policy[field][default] in policy[field][allowed],
                    f'Policy {name}: {field} default must appear in its allowlist')
        require(policy['autoscaling']['min_workers'] <= policy['autoscaling']['max_workers'],
                f'Policy {name}: min_workers must not exceed max_workers')
        ml_runtimes = ['-cpu-ml-' in version for version in policy['runtime']['allowed_versions']]
        require(not any(ml_runtimes) or (all(ml_runtimes) and policy['data_security_mode'] == 'SINGLE_USER'),
                f'Policy {name}: CPU ML runtimes require dedicated SINGLE_USER mode; do not mix runtime families')
    for name, warehouse in compute['sql_warehouses'].items():
        require(warehouse['min_clusters'] <= warehouse['max_clusters'],
                f'Warehouse {name}: min_clusters must not exceed max_clusters')


def load_compute(foundation=FOUNDATION, environment='dev', workspace='demo'):
    """Read personas, verified provisioning declarations and compute, independently of datasets."""
    bundle = load_workspace_access(foundation, environment, workspace)
    path = Path(foundation) / 'platform/compute/dev.yaml'
    bundle['compute'] = load_yaml(path)
    check_schema(bundle['compute'], 'compute', str(path))
    validate_compute(bundle['compute'])
    for name, persona in bundle['roles']['personas'].items():
        require(set(persona['cluster_policies']) <= bundle['compute']['cluster_policies'].keys(),
                f'Persona {name} references an unknown compute policy')
        require(persona['sql_warehouses'].keys() <= bundle['compute']['sql_warehouses'].keys(),
                f'Persona {name} references an unknown SQL warehouse')
    return bundle


def validate_bundle(bundle):
    """Cross-file authorization; schemas alone do not authorize an access request."""
    roles = bundle['roles']
    packages, personas = roles['packages'], roles['personas']
    groups = bundle['principals']['groups']
    resources, compute = bundle['resources'], bundle['compute']
    validate_persona_access(roles)
    for name, package in packages.items():
        require(package, f'Package {name} must define at least one object type')
    for name, persona in personas.items():
        require(set(persona['allowed_packages']) <= packages.keys(),
                f'Persona {name} references an unknown package')
        require(set(persona['cluster_policies']) <= compute['cluster_policies'].keys(),
                f'Persona {name} references an unknown compute policy')
        require(persona['sql_warehouses'].keys() <= compute['sql_warehouses'].keys(),
                f'Persona {name} references an unknown SQL warehouse')
        if name == 'admins':
            require(not persona['allowed_packages'], 'Admin data access uses explicit ownership, not packages')

    names, account_ids = set(), set()
    for key, group in groups.items():
        require(group['display_name'] not in names, 'Duplicate group display name')
        names.add(group['display_name'])
        group_id = group.get('account_group_id')
        require((group['lifecycle'] == 'external') == (group_id is not None),
                f'Group {key}: external requires account_group_id; create/terraform must omit it')
        if group_id:
            require(group_id not in account_ids, 'Duplicate account group ID')
            account_ids.add(group_id)

    for catalog, dataset in resources['datasets'].items():
        require(dataset['approval_owner'] in bundle['reviewers']['data_owners'],
                f'Catalog {catalog} has an unknown approval owner')
        for schema, limits in dataset['schemas'].items():
            require(set(limits['allowed_packages']) <= packages.keys(),
                    f'{catalog}.{schema} references an unknown package')
    for workload, limits in resources['workloads'].items():
        require(limits['principal'] in groups, f'Workload {workload} references an unknown group')
        require(set(limits['allowed_catalogs']) <= resources['datasets'].keys(),
                f'Workload {workload} references an unknown catalog')

    validate_compute(compute)

    target = bundle['target']
    if target['active']:
        require(int(target['workspace_id']) > 0 and int(target['metastore_id'].replace('-', ''), 16) > 0
                and 'replace-me' not in target['workspace_url'],
                'An active target requires real workspace/metastore identities')
        require('replace-me' not in json.dumps(bundle['reviewers']),
                'An active target requires real reviewer mappings')

    for request in bundle['workloads']:
        workload = request['workload']
        limits = resources['workloads'][workload]
        persona = groups[limits['principal']]['persona']
        require(request['persona'] == persona,
                f'{workload}: requested persona must match platform-approved persona {persona}')
        ids = set()
        for grant in request['data_access']:
            label = f'{workload}/{grant["id"]}'
            require(grant['id'] not in ids, f'Duplicate grant ID: {label}')
            ids.add(grant['id'])
            package = grant['access']
            kind = 'table' if 'table' in grant else 'schema' if 'schema' in grant else 'catalog'
            require(package in personas[persona]['allowed_packages'],
                    f'{label}: persona cannot request package {package}')
            require(package in packages and kind in packages[package],
                    f'{label}: package {package} does not support {kind}')
            catalog = grant['catalog']
            require(catalog in limits['allowed_catalogs'], f'{label}: workload cannot request this catalog')
            if kind != 'catalog':
                schemas = resources['datasets'][catalog]['schemas']
                require(grant['schema'] in schemas, f'{label}: schema is not registered')
                require(package in schemas[grant['schema']]['allowed_packages'],
                        f'{label}: resource does not permit package {package}')
