#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 <team-id> <user-id> <team-policy-name>"
    exit 1
fi

TEAM_ID="$1"
USER_ID="$2"
POLICY_NAME="$3"

POLICY_FILE="$LLM_GATEWAY_CONFIG_DIR/policies/teams/${POLICY_NAME}.yaml"

POLICY_JSON="$(
    python3 "$REPO_ROOT/scripts/lib/read-team-policy.py" \
        "$POLICY_FILE"
)"

MEMBER_BUDGET="$(
python3 - "$POLICY_JSON" <<'PY'
import json
import sys

policy = json.loads(sys.argv[1])

print(
    policy["limits"]["member"]["monthly_budget_usd"]
)
PY
)"

BODY="$(
python3 - "$TEAM_ID" "$USER_ID" "$MEMBER_BUDGET" <<'PY'
import json
import sys

team_id = sys.argv[1]
user_id = sys.argv[2]
member_budget = float(sys.argv[3])

print(json.dumps({
    "team_id": team_id,
    "max_budget_in_team": member_budget,
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