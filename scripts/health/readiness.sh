#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/common.sh"

echo "Checking LiteLLM readiness..."

curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 10 \
    "${LITELLM_BASE_URL}/health/readiness" \
    >/dev/null

# HTTP readiness may return a cached 200 while a dependency is down.
"$SCRIPT_DIR/dependencies.sh" >/dev/null
echo "LiteLLM readiness (HTTP + dependencies): OK"
