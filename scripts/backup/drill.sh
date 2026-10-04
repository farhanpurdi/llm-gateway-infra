#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd
)"

BACKUP_DIR="$SCRIPT_DIR/../../backups"

echo
echo "======================================"
echo "BACKUP / RESTORE DRILL"
echo "======================================"
echo

"$SCRIPT_DIR/backup-postgres.sh"

BACKUP_FILE=""

for file in "$BACKUP_DIR"/*.dump; do
  if [ ! -e "$file" ]; then
    continue
  fi

  if [ -z "$BACKUP_FILE" ] || \
     [ "$file" -nt "$BACKUP_FILE" ]; then
    BACKUP_FILE="$file"
  fi
done

if [ -z "$BACKUP_FILE" ]; then
  echo "ERROR: no backup file found in:"
  echo "$BACKUP_DIR"
  exit 1
fi

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