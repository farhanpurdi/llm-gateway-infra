#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/common.sh"

required_env POSTGRES_USER
required_env POSTGRES_DB

echo "======================================"
echo "Dependency Health"
echo "======================================"

echo
echo "[1/2] PostgreSQL"

docker exec \
    llm-gateway-postgres \
    pg_isready \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB"

echo "PostgreSQL: OK"


echo
echo "[2/2] Redis"

REDIS_RESULT="$(
    docker exec \
        llm-gateway-redis \
        redis-cli ping
)"

if [ "$REDIS_RESULT" != "PONG" ]; then
    echo "Redis: FAILED"
    exit 1
fi

echo "Redis: OK"

echo
echo "All dependencies: OK"