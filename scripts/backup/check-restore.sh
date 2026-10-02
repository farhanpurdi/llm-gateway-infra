#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

required_env POSTGRES_USER

RESTORE_DB="${RESTORE_DB:-litellm_restore_test}"

echo "======================================"
echo "Restore Verification"
echo "======================================"

echo
echo "Database:"
echo "  $RESTORE_DB"

TABLE_COUNT="$(
    docker exec \
        llm-gateway-postgres \
        psql \
        -U "$POSTGRES_USER" \
        -d "$RESTORE_DB" \
        -tAc "
            SELECT COUNT(*)
            FROM pg_tables
            WHERE schemaname = 'public';
        " \
        | tr -d ' '
)"

echo
echo "Public tables:"
echo "  $TABLE_COUNT"

if [ "$TABLE_COUNT" -eq 0 ]; then
    echo "ERROR: restored database contains no public tables."
    exit 1
fi

echo
echo "Listing tables..."

docker exec \
    llm-gateway-postgres \
    psql \
        -U "$POSTGRES_USER" \
        -d "$RESTORE_DB" \
        -c '\dt'

echo
echo "Restore verification: PASS"