#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 1 ]; then
    echo "Usage:"
    echo "  $0 <user-id>"
    echo
    echo "Example:"
    echo "  $0 pur@company.com"
    exit 1
fi

USER_ID="$1"

echo "Creating LiteLLM user:"
echo "  user_id: $USER_ID"
echo

BODY="$(
python3 - "$USER_ID" <<'PY'
import json
import sys

user_id = sys.argv[1]

print(json.dumps({
    "user_id": user_id,
    "user_role": "internal_user",
    "auto_create_key": False,
}))
PY
)"

litellm_admin_request \
    POST \
    /user/new \
    "$BODY" \
    | python3 -m json.tool