#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [ "$#" -lt 1 ]; then
    echo "Usage:"
    echo "  $0 <virtual-key>"
    exit 1
fi

KEY="$1"

BODY="$(
python3 - "$KEY" <<'PY'
import json
import sys

print(json.dumps({
    "key": sys.argv[1]
}))
PY
)"

litellm_admin_request \
    POST \
    /key/block \
    "$BODY" \
    | python3 -m json.tool