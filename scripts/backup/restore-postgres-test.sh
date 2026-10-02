#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

required_env POSTGRES_USER

if [ "$#" -ne 1 ]; then
  echo "Usage:"
  echo "  $0 <backup.dump>"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: backup file not found:"
  echo "$BACKUP_FILE"
  exit 1
fi

RESTORE_DB="${RESTORE_DB:-litellm_restore_test}"

echo "======================================"
echo "PostgreSQL Restore Drill"
echo "======================================"

echo
echo "Backup:"
echo "  $BACKUP_FILE"

echo
echo "Temporary database:"
echo "  $RESTORE_DB"

echo
echo "Dropping previous test database if present..."

docker exec \
    llm-gateway-postgres \
    dropdb \
        -U "$POSTGRES_USER" \
        --if-exists \
        "$RESTORE_DB"

echo "Creating temporary database..."

docker exec \
    llm-gateway-postgres \
    createdb \
        -U "$POSTGRES_USER" \
        "$RESTORE_DB"

echo "Restoring..."

cat "$BACKUP_FILE" \
    | docker exec -i \
        llm-gateway-postgres \
        pg_restore \
            -U "$POSTGRES_USER" \
            -d "$RESTORE_DB" \
            --no-owner \
            --no-acl

echo
echo "Restore completed."
echo "Database:"
echo "  $RESTORE_DB"