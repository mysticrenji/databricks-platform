#!/usr/bin/env python3
"""Create and populate GitHub Environments for one runnable workspace.

Defaults to a dry run. Use --execute to create/update GitHub Environments,
variables, and the Databricks OAuth secret.
"""
import argparse
import getpass
import os
from pathlib import Path
import shlex
import subprocess
import sys

FOUNDATION = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(FOUNDATION / "tools" / "environment"))

from environment import ConfigError, load, state_keys, validate  # noqa: E402


def command(args, *, execute, secret_input=None, sensitive=False):
    """Run one GitHub CLI command, or print a safe dry-run representation."""
    if not execute:
        display = shlex.join(args)
        if sensitive:
            display += " <secret provided through standard input>"
        print(f"Would run: {display}")
        return
    subprocess.run(args, input=secret_input, text=True, check=True)


def repository(value):
    if value:
        return value
    return subprocess.check_output(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        text=True,
    ).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("dev", "staging"), help="Workspace configuration to prepare")
    parser.add_argument("--workspace", required=True, help="Workspace identifier within the environment, matching workspace.name in YAML")
    parser.add_argument("--repo", help="GitHub repository as OWNER/REPOSITORY; defaults to the current gh repository")
    parser.add_argument("--config", type=Path, help="Override the target YAML path")
    parser.add_argument("--state-bucket", required=True, help="Existing S3 Terraform state bucket")
    parser.add_argument("--state-region", help="State bucket region; defaults to the YAML AWS region")
    parser.add_argument("--infra-state-key", help="Must match databricks/<environment>/<workspace>/01-infra.tfstate")
    parser.add_argument("--account-state-key", help="Must match databricks/<environment>/<workspace>/02-account.tfstate")
    parser.add_argument("--data-access-state-key", help="Actual root 03 state key; needed for deprovisioning checks")
    parser.add_argument("--workspace-state-key", help="Actual root 04 state key; needed for deprovisioning checks")
    parser.add_argument("--databricks-client-id", required=True, help="Databricks OAuth service-principal client ID")
    parser.add_argument("--enable-apply", action="store_true", help="Set ENVIRONMENT_YAML_APPLY_ENABLED=true in the apply environment")
    parser.add_argument("--enable-destroy", action="store_true", help="Opt in to the protected deprovisioning workflow")
    parser.add_argument("--execute", action="store_true", help="Create/update GitHub Environments; without it, print a dry run")
    args = parser.parse_args()

    config_path = args.config or FOUNDATION / "platform" / "environments" / args.target / f"{args.workspace}.yaml"
    try:
        config = validate(load(config_path))
    except ConfigError as exc:
        parser.error(str(exc))
    if config["environment"]["name"] != args.target:
        parser.error(f"{config_path} must declare environment.name: {args.target}")
    if config["workspace"]["name"] != args.workspace:
        parser.error(f"{config_path} must declare workspace.name: {args.workspace}")
    try:
        workflow_config_path = config_path.resolve().relative_to(FOUNDATION.parents[1]).as_posix()
    except ValueError:
        parser.error("--config must be inside this repository so GitHub Actions can read it")

    repo = repository(args.repo)
    state_region = args.state_region or config["environment"]["aws_region"]
    keys = state_keys(config)
    supplied = {'01-infra': args.infra_state_key, '02-account': args.account_state_key,
                '03-data-access': args.data_access_state_key, '04-workspace': args.workspace_state_key}
    if any(value is not None and value != keys[root] for root, value in supplied.items()):
        parser.error("State keys must match the selected environment/workspace namespace")

    variables = {
        "ENVIRONMENT_CONFIG_PATH": workflow_config_path,
        "AWS_DEPLOYMENT_ROLE_ARN": config["environment"]["deployment_role_arn"],
        "DATABRICKS_ACCOUNT_ID": config["databricks"]["account_id"],
        "DATABRICKS_CLIENT_ID": args.databricks_client_id,
        "TF_STATE_BUCKET": args.state_bucket,
        "TF_STATE_REGION": state_region,
        "TF_INFRA_STATE_KEY": keys['01-infra'],
        "TF_ACCOUNT_STATE_KEY": keys['02-account'],
        "TF_DATA_ACCESS_STATE_KEY": keys['03-data-access'],
        "TF_WORKSPACE_STATE_KEY": keys['04-workspace'],
    }
    secret = None
    if args.execute:
        secret = os.environ.get("DATABRICKS_CLIENT_SECRET") or getpass.getpass("Databricks OAuth client secret: ")
        if not secret:
            parser.error("DATABRICKS_CLIENT_SECRET must not be empty")

    for phase in ("plan", "apply"):
        environment = f"{args.target}-{args.workspace}-{phase}"
        command(["gh", "api", "--method", "PUT", f"repos/{repo}/environments/{environment}"], execute=args.execute)
        for name, value in variables.items():
            command(["gh", "variable", "set", name, "--repo", repo, "--env", environment, "--body", value], execute=args.execute)
        if phase == "apply":
            command(["gh", "variable", "set", "ENVIRONMENT_YAML_APPLY_ENABLED", "--repo", repo, "--env", environment, "--body", "true" if args.enable_apply else "false"], execute=args.execute)
            command(["gh", "variable", "set", "ENVIRONMENT_YAML_DESTROY_ENABLED", "--repo", repo, "--env", environment, "--body", "true" if args.enable_destroy else "false"], execute=args.execute)
        command(["gh", "secret", "set", "DATABRICKS_CLIENT_SECRET", "--repo", repo, "--env", environment], execute=args.execute, secret_input=secret, sensitive=True)

    print(f"Prepared {args.target}-{args.workspace}-plan and {args.target}-{args.workspace}-apply for {repo}.")
    if not args.execute:
        print("Review the commands above, then rerun with --execute. You will be prompted for DATABRICKS_CLIENT_SECRET.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Setup failed: {exc}", file=sys.stderr)
        sys.exit(1)
