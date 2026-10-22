#!/bin/bash
set -eu
echo "Hello world from the Databricks cluster-scoped init script!"
echo "Node: $(hostname)"
echo "Startup time (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
