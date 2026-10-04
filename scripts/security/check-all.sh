#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd
)"

echo
echo "======================================"
echo "LLM Gateway Infrastructure Security"
echo "======================================"

echo
echo "[1/3] Secret scanning"

"$SCRIPT_DIR/scan-secrets.sh"

echo
echo "[2/3] Python dependency audit"

"$SCRIPT_DIR/audit-python.sh" \
  "$SCRIPT_DIR/../requirements.txt"

echo
echo "[3/3] Container vulnerability scan"

"$SCRIPT_DIR/scan-containers.sh"

echo
echo "======================================"
echo "ALL SECURITY CHECKS PASSED"
echo "======================================"