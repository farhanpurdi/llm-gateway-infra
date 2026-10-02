#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/common.sh"

echo "Checking LiteLLM readiness..."

curl \
    --fail \
    --silent \
    --show-error \
    "${LITELLM_BASE_URL}/health/readiness" \
    >/dev/null

echo "LiteLLM readiness: OK"