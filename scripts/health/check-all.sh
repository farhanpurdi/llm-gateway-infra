#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "======================================"
echo "LLM Gateway Health Check"
echo "======================================"
echo

"$SCRIPT_DIR/liveness.sh"

echo
"$SCRIPT_DIR/readiness.sh"

echo
"$SCRIPT_DIR/dependencies.sh"

echo
"$SCRIPT_DIR/functional.sh"

echo
echo "======================================"
echo "ALL HEALTH CHECKS PASSED"
echo "======================================"