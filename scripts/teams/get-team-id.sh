#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 <team-alias>"
    exit 1
fi

TEAM_ALIAS="$1"

RESPONSE="$(
    curl --fail-with-body -sS \
        "${LITELLM_BASE_URL}/user/info?user_id=default_user_id" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
)"

TEAM_ID="$(
python3 - "$TEAM_ALIAS" "$RESPONSE" <<'PY'
import json
import sys

team_alias = sys.argv[1]
data = json.loads(sys.argv[2])

teams = data.get("teams", [])

for team in teams:
    if team.get("team_alias") == team_alias:
        print(team["team_id"])
        sys.exit(0)

print(
    f"ERROR: team not found: {team_alias}",
    file=sys.stderr,
)
sys.exit(1)
PY
)"

printf '%s\n' "$TEAM_ID"