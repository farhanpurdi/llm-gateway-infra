#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <backup.dump>"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup not found."
    exit 1
fi

TEMP_DB="litellm_restore_test"

docker exec llm-gateway-postgres \
    dropdb \
    -U "$POSTGRES_USER" \
    --if-exists \
    "$TEMP_DB"

docker exec llm-gateway-postgres \
    createdb \
    -U "$POSTGRES_USER" \
    "$TEMP_DB"

    cat "$BACKUP_FILE" \
    | docker exec -i \
        llm-gateway-postgres \
        pg_restore \
            -U "$POSTGRES_USER" \
            -d "$TEMP_DB"

echo "Restore completed into:"
echo "$TEMP_DB"