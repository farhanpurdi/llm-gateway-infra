#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env not found at:"
    echo "$ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a


required_env() {
    local name="$1"

    if [ -z "${!name:-}" ]; then
        echo "ERROR: required environment variable '$name' is missing."
        exit 1
    fi
}


required_env LITELLM_BASE_URL
required_env LITELLM_MASTER_KEY


litellm_admin_request() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    if [ -n "$body" ]; then
        curl --fail-with-body -sS \
        -X "$method" \
        "${LITELLM_BASE_URL}${path}" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "$body"
    else
        curl --fail-with-body -sS \
        -X "$method" \
        "${LITELLM_BASE_URL}${path}" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
    fi
}