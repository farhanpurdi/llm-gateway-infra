#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/common.sh"

required_env HEALTHCHECK_API_KEY

echo "Checking authenticated model catalog..."

RESPONSE="$(
    curl \
        --fail \
        --silent \
        --show-error \
        "${LITELLM_BASE_URL}/v1/models" \
        -H "Authorization: Bearer ${HEALTHCHECK_API_KEY}"
)"

python3 - "$RESPONSE" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])

models = {
    item["id"]
    for item in data.get("data", [])
}

required = {
    "company-fast",
    "company-coding",
}

missing = required - models

if missing:
    print(
        "Functional health FAILED. "
        f"Missing models: {sorted(missing)}",
        file=sys.stderr,
    )
    sys.exit(1)

print("Functional health: OK")
print("Available required models:")
for model in sorted(required):
    print(f"  - {model}")
PY