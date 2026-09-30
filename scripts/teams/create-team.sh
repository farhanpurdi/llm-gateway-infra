#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 2 ]; then
    echo "Usage:"
    echo "  $0 <team-name> <model> [model...]"
    echo
    echo "Example:"
    echo "  $0 engineering company-fast company-coding"
    exit 1
fi

TEAM_ALIAS="$1"
shift

BODY="$(
python3 - "$TEAM_ALIAS" "$@" <<'PY'
import json
import sys

team_alias = sys.argv[1]
models = sys.argv[2:]

print(json.dumps({
    "team_alias": team_alias,
    "models": models,
    "max_budget": 5,
    "budget_duration": "30d",
    "rpm_limit": 60,
    "tpm_limit": 200000,
}))
PY
)"

litellm_admin_request \
    POST \
    /team/new \
    "$BODY" \
    | python3 -m json.tool