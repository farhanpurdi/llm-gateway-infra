#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 <team-policy-name>"
    echo
    echo "Example:"
    echo "  $0 engineering"
    exit 1
fi

POLICY_NAME="$1"

POLICY_FILE="$LLM_GATEWAY_CONFIG_DIR/policies/teams/${POLICY_NAME}.yaml"

if [ ! -f "$POLICY_FILE" ]; then
    echo "ERROR: team policy not found:"
    echo "$POLICY_FILE"
    exit 1
fi

POLICY_JSON="$(
    python3 "$REPO_ROOT/scripts/lib/read-team-policy.py" \
        "$POLICY_FILE"
)"

BODY="$(
python3 - "$POLICY_JSON" <<'PY'
import json
import sys

policy = json.loads(sys.argv[1])

team = policy["limits"]["team"]

print(json.dumps({
    "team_alias": policy["name"],
    "models": policy["models"],
    "max_budget": team["monthly_budget_usd"],
    "budget_duration": "30d",
    "rpm_limit": team["rpm"],
    "tpm_limit": team["tpm"],
    "metadata": {
        "managed_by": "llm-gateway-config",
        "policy": policy["name"],
    },
}))
PY
)"

echo "Creating team from policy:"
echo "  policy: $POLICY_NAME"
echo "  file:   $POLICY_FILE"
echo

litellm_admin_request \
    POST \
    /team/new \
    "$BODY" \
    | python3 -m json.tool