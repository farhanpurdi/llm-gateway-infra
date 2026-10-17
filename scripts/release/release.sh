#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
export REPO_ROOT LLM_GATEWAY_CONFIG_DIR ENV_FILE
exec python3 "$SCRIPT_DIR/manage.py" "$@"
