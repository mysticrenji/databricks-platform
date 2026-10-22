#!/usr/bin/env python3
"""Validate and preview ADR 0005 dev/demo intent offline. No API calls or apply."""
import argparse
import json
import sys

from configuration import ConfigError, load_bundle
from desired import preview


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('validate', 'preview'))
    parser.add_argument('--environment', required=True)
    parser.add_argument('--workspace', required=True)
    args = parser.parse_args(argv)
    try:
        bundle = load_bundle(environment=args.environment, workspace=args.workspace)
        if args.command == 'validate':
            print('Valid offline configuration: dev/demo (no live identity or availability checks)')
        else:
            print(json.dumps(preview(bundle), indent=2, sort_keys=True))
    except ConfigError as exc:
        print(f'Configuration error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
