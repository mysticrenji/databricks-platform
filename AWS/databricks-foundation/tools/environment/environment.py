#!/usr/bin/env python3
"""Validate environment intent and render inputs; never call a cloud API."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import sys

import jsonschema
import yaml

HERE = Path(__file__).resolve().parent
# Reviewed baseline from foundation README; update with the platform support review.
REGIONS = set('ap-northeast-1 ap-northeast-2 ap-south-1 ap-southeast-1 ap-southeast-2 ap-southeast-3 ca-central-1 eu-central-1 eu-west-1 eu-west-2 eu-west-3 sa-east-1 us-east-1 us-east-2 us-west-1 us-west-2'.split())
ROOTS = ('01-infra', '02-account')
ALL_ROOTS = ('01-infra', '02-account', '03-data-access', '04-workspace')


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


def load(path):
    try:
        return yaml.load(Path(path).read_text(), Loader=StrictLoader)
    except (OSError, yaml.YAMLError) as exc:
        raise ConfigError(f'Cannot read environment YAML: {exc}') from exc


def validate(config, example=False):
    schema = json.loads((HERE / 'schema.json').read_text())
    errors = sorted(jsonschema.Draft202012Validator(schema).iter_errors(config), key=lambda e: str(list(e.path)))
    if errors:
        error = errors[0]
        raise ConfigError(f'{".".join(map(str, error.path)) or "document"}: {error.message}')
    env, network = config['environment'], config['network']
    region = env['aws_region']
    if region not in REGIONS:
        raise ConfigError('aws_region is not in the reviewed commercial AWS region list')
    role = re.fullmatch(r'arn:aws:iam::([0-9]{12}):role/([A-Za-z0-9+=,.@_/-]+)', env['deployment_role_arn'])
    if not role or role[1] != env['aws_account_id']:
        raise ConfigError('deployment_role_arn must be an IAM role in aws_account_id')
    bucket = config['storage']['workspace_bucket_name']
    invalid_name = not re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', bucket)
    ip_name = re.fullmatch(r'\d+\.\d+\.\d+\.\d+', bucket)
    reserved_name = bucket.startswith(('xn--', 'sthree-', 'amzn-s3-demo-')) or bucket.endswith(
        ('-s3alias', '--ol-s3', '.mrap', '--x-s3', '--table-s3')
    )
    if invalid_name or '..' in bucket or ip_name or reserved_name:
        raise ConfigError('workspace_bucket_name must be a valid S3 bucket name')
    if not example:
        text = json.dumps(config).lower()
        if any(marker in text for marker in ('replace-me', 'replace_with', '00000000-0000-0000-0000-000000000000', '111111111111')):
            raise ConfigError('Replace example placeholders before deployment')
    try:
        vpc = ipaddress.IPv4Network(network['vpc_cidr'])
        if not 16 <= vpc.prefixlen <= 28:
            raise ConfigError('VPC prefix must be /16 through /28')
        seen = []
        for field, limits in [('workspace_subnets', (17, 26)), ('nat_subnets', (16, 28)), ('endpoint_subnets', (17, 27))]:
            azs = []
            for key, subnet in network[field].items():
                label = f'network.{field}.{key}'
                cidr = ipaddress.IPv4Network(subnet['cidr_block'])
                if not limits[0] <= cidr.prefixlen <= limits[1] or not cidr.subnet_of(vpc):
                    raise ConfigError(f'{label}: invalid subnet size or outside VPC')
                for other_label, other in seen:
                    if cidr.overlaps(other):
                        raise ConfigError(f'{label}: overlaps {other_label}')
                seen.append((label, cidr))
                az = subnet['availability_zone']
                if not re.fullmatch(re.escape(region) + r'[a-z]', az):
                    raise ConfigError(f'{label}: availability zone must belong to {region}')
                if az in azs:
                    raise ConfigError(f'{field}: availability zones must be unique')
                azs.append(az)
            if field == 'workspace_subnets' and len(azs) < 2:
                raise ConfigError('Workspace requires at least two availability zones')
        routes = network['workspace_subnet_nat_gateway_keys']
        if set(routes) != set(network['workspace_subnets']):
            raise ConfigError('NAT mapping must cover exactly the workspace subnet keys')
        mode = network['nat_gateway_mode']
        if mode == 'single':
            if len(network['nat_subnets']) != 1:
                raise ConfigError('single NAT mode requires exactly one NAT subnet')
            nat_key = next(iter(network['nat_subnets']))
            if any(mapped_key != nat_key for mapped_key in routes.values()):
                raise ConfigError('single NAT mode must map every workspace subnet to the only NAT subnet')
        else:
            for key, nat_key in routes.items():
                nat = network['nat_subnets'].get(nat_key)
                if nat is None or nat['availability_zone'] != network['workspace_subnets'][key]['availability_zone']:
                    raise ConfigError(f'NAT mapping {key} must reference a same-AZ NAT subnet in per_az mode')
    except ValueError as exc:
        raise ConfigError(str(exc)) from exc
    return config


def render(config):
    env, db, net = config['environment'], config['databricks'], config['network']
    identity = {'environment_name': env['name'], 'workspace_key': config['workspace']['name']}
    return {
        '01-infra': {
            **identity,
            'aws_region': env['aws_region'], 'aws_account_id': env['aws_account_id'],
            'databricks_account_id': db['account_id'],
            'vpc_cidr_block': net['vpc_cidr'],
            **{key: net[key] for key in ('workspace_subnets', 'nat_subnets', 'endpoint_subnets', 'workspace_subnet_nat_gateway_keys')},
            'root_storage_bucket_name': config['storage']['workspace_bucket_name'],
            'enable_customer_managed_kms': config['features']['customer_managed_kms'],
            'enable_observability': config['features']['observability'],
        },
        '02-account': identity | {'workspace_name': f'{env["name"]}-{config["workspace"]["name"]}',
                                  'pricing_tier': db['pricing_tier'], 'databricks_account_id': db['account_id']},
    }


def state_keys(config):
    prefix = f'databricks/{config["environment"]["name"]}/{config["workspace"]["name"]}'
    return {root: f'{prefix}/{root}.tfstate' for root in ALL_ROOTS}


def check_target(config):
    if os.environ.get('TARGET_ENVIRONMENT', config['environment']['name']) != config['environment']['name']:
        raise ConfigError('YAML environment.name must match TARGET_ENVIRONMENT')
    if os.environ.get('TARGET_WORKSPACE', config['workspace']['name']) != config['workspace']['name']:
        raise ConfigError('YAML workspace.name must match TARGET_WORKSPACE')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('validate', 'render'))
    parser.add_argument('config', type=Path)
    parser.add_argument('--example', action='store_true', help='Validate documentation placeholders; validation only')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        if args.example and args.command != 'validate':
            raise ConfigError('--example is only allowed with validate')
        config = validate(load(args.config), example=args.example)
        check_target(config)
        if args.command == 'render':
            if args.output is None:
                raise ConfigError('render requires --output DIRECTORY')
            args.output.mkdir(parents=True, exist_ok=True)
            for root, values in render(config).items():
                (args.output / f'{root}.tfvars.json').write_text(json.dumps(values, sort_keys=True, indent=2) + '\n')
        print(f'Valid environment/workspace: {config["environment"]["name"]}/{config["workspace"]["name"]}')
    except ConfigError as exc:
        print(f'Configuration error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
