#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage:"
  echo "  $0 <backup.dump>"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: backup does not exist:"
  echo "$BACKUP_FILE"
  exit 1
fi

if [ ! -s "$BACKUP_FILE" ]; then
  echo "ERROR: backup is empty."
  exit 1
fi

TEMP_FILE="$(mktemp)"

cleanup() {
  rm -f "$TEMP_FILE"
}

trap cleanup EXIT

echo "======================================"
echo "Backup Verification"
echo "======================================"

echo
echo "Checking archive..."

cat "$BACKUP_FILE" \
  | docker exec -i \
      llm-gateway-postgres \
      pg_restore \
        --list \
  > "$TEMP_FILE"

ENTRY_COUNT="$(
  awk '
    NF && $0 !~ /^;/ {
      count++
    }

    END {
      print count + 0
    }
  ' "$TEMP_FILE"
)"

if [ "$ENTRY_COUNT" -eq 0 ]; then
  echo "ERROR: no archive entries found."
  exit 1
fi

echo "Archive readable: OK"
echo "Archive entries: $ENTRY_COUNT"

echo
echo "Backup verification: PASS"