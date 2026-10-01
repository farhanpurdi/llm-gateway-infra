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


CONFIG_DIR_RAW="${LLM_GATEWAY_CONFIG_DIR:-../llm-gateway-config}"

if [[ "$CONFIG_DIR_RAW" = /* ]]; then
    LLM_GATEWAY_CONFIG_DIR="$CONFIG_DIR_RAW"
else
    LLM_GATEWAY_CONFIG_DIR="$REPO_ROOT/$CONFIG_DIR_RAW"
fi

if [ ! -d "$LLM_GATEWAY_CONFIG_DIR" ]; then
    echo "ERROR: config repository not found:"
    echo "$LLM_GATEWAY_CONFIG_DIR"
    exit 1
fi


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