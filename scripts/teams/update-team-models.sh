#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 2 ]; then
    echo "Usage:"
    echo "  $0 <team-id> <model> [model...]"
    exit 1
fi

TEAM_ID="$1"
shift

BODY="$(
python3 - "$TEAM_ID" "$@" <<'PY'
import json
import sys

team_id = sys.argv[1]
models = sys.argv[2:]

print(json.dumps({
    "team_id": team_id,
    "models": models,
}))
PY
)"

litellm_admin_request \
    POST \
    /team/update \
    "$BODY" \
    | python3 -m json.tool