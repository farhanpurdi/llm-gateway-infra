#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 2 ]; then
    echo "Usage:"
    echo "  $0 <team-id> <user-id>"
    exit 1
fi

TEAM_ID="$1"
USER_ID="$2"

BODY="$(
python3 - "$TEAM_ID" "$USER_ID" <<'PY'
import json
import sys

team_id = sys.argv[1]
user_id = sys.argv[2]

print(json.dumps({
    "team_id": team_id,
    "max_budget_in_team": 1,
    "member": {
        "role": "user",
        "user_id": user_id,
    }
}))
PY
)"

litellm_admin_request \
    POST \
    /team/member_add \
    "$BODY" \
    | python3 -m json.tool