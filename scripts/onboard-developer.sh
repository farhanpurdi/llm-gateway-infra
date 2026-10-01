#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -lt 2 ]; then
    echo "Usage:"
    echo "  $0 <user-id> <team-id>"
    exit 1
fi

USER_ID="$1"
TEAM_ID="$2"
POLICY_NAME="$3"

KEY_ALIAS="$(
python3 - "$USER_ID" <<'PY'
import re
import sys

value = sys.argv[1].lower()
value = re.sub(r'[^a-z0-9]+', '-', value)
value = value.strip('-')

print(f"{value}-opencode")
PY
)"

echo "======================================"
echo "Developer onboarding"
echo "======================================"
echo
echo "User:"
echo "  $USER_ID"
echo
echo "Team:"
echo "  $TEAM_ID"
echo

"$SCRIPT_DIR/users/create-user.sh" \
    "$USER_ID"

echo
echo "Adding user to team..."
echo

"$SCRIPT_DIR/teams/add-member.sh" \
    "$TEAM_ID" \
    "$USER_ID" \
    "$POLICY_NAME"

echo
echo "Creating developer key..."
echo

"$SCRIPT_DIR/keys/create-key.sh" \
    "$USER_ID" \
    "$TEAM_ID" \
    "$KEY_ALIAS"