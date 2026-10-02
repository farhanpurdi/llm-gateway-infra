#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "======================================"
echo "BACKUP / RESTORE DRILL"
echo "======================================"
echo

"$SCRIPT_DIR/backup-postgres.sh"

BACKUP_FILE="$(
    ls -1t "$SCRIPT_DIR/../../backups/"*.dump \
        | head -n 1
)"

echo
echo "Using:"
echo "$BACKUP_FILE"
echo

"$SCRIPT_DIR/verify-backup.sh" \
    "$BACKUP_FILE"

echo

"$SCRIPT_DIR/restore-postgres-test.sh" \
    "$BACKUP_FILE"

echo

"$SCRIPT_DIR/check-restore.sh"

echo
echo "======================================"
echo "BACKUP / RESTORE DRILL PASSED"
echo "======================================"