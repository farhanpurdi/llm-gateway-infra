#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

required_env POSTGRES_DB
required_env POSTGRES_USER

BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/litellm-$TIMESTAMP.dump"

echo "======================================"
echo "PostgreSQL Backup"
echo "======================================"
echo
echo "Database:"
echo "  $POSTGRES_DB"
echo
echo "Destination:"
echo "  $BACKUP_FILE"
echo

docker exec \
    llm-gateway-postgres \
    pg_dump \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -Fc \
        --no-owner \
        --no-acl \
    > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
    echo "ERROR: backup file is empty."
    rm -f "$BACKUP_FILE"
    exit 1
fi

chmod 600 "$BACKUP_FILE"

echo
echo "Backup completed successfully."
echo
echo "Size:"
du -h "$BACKUP_FILE"

echo
echo "Backup file:"
printf '%s\n' "$BACKUP_FILE"