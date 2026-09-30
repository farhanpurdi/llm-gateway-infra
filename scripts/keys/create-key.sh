#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 3 ]; then
    echo "Usage:"
    echo "  $0 <user-id> <team-id> <key-alias>"
    exit 1
fi

USER_ID="$1"
TEAM_ID="$2"
KEY_ALIAS="$3"

BODY="$(
python3 - "$USER_ID" "$TEAM_ID" "$KEY_ALIAS" <<'PY'
import json
import sys

user_id = sys.argv[1]
team_id = sys.argv[2]
key_alias = sys.argv[3]

print(json.dumps({
    "user_id": user_id,
    "team_id": team_id,
    "key_alias": key_alias,
    "models": [
        "all-team-models"
    ],
    "metadata": {
        "environment": "development",
        "purpose": "developer-opencode",
    }
}))
PY
)"

RESPONSE="$(
    litellm_admin_request \
        POST \
        /key/generate \
        "$BODY"
)"

KEY="$(
    printf '%s' "$RESPONSE" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])'
)"

echo
echo "Virtual key created successfully."
echo
echo "User:"
echo "  $USER_ID"
echo
echo "Team:"
echo "  $TEAM_ID"
echo
echo "Key alias:"
echo "  $KEY_ALIAS"
echo
echo "IMPORTANT:"
echo "This key is displayed ONCE."
echo "Store it securely and do not commit it to Git."
echo
printf '%s\n' "$KEY"