#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 1 ]; then
    echo "Usage:"
    echo "  $0 <team-id>"
    exit 1
fi

TEAM_ID="$1"

curl --fail-with-body -sS \
    "${LITELLM_BASE_URL}/team/info?team_id=${TEAM_ID}" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    | python3 -m json.tool