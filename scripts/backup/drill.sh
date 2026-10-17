#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/restore-target.sh"
if [ "${1:-}" != "--quiesce" ] || [ "$#" -ne 1 ]; then
  echo "Usage: $0 --quiesce (briefly stops the existing gateway; no new container)" >&2
  exit 1
fi
TEMP_DIR="$(mktemp -d)"
restart_needed=false
cleanup() {
  if [ "$restart_needed" = true ]; then
    docker start "$GATEWAY_CONTAINER" >/dev/null
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
if [ "$(docker inspect -f '{{.State.Running}}' "$GATEWAY_CONTAINER")" != true ]; then
  echo "ERROR: gateway must be running before the drill" >&2
  exit 1
fi
# Stop only the existing gateway so no test/inference writes race the comparison.
restart_needed=true
docker stop --time 30 "$GATEWAY_CONTAINER" >/dev/null
BACKUP_FILE="$("$SCRIPT_DIR/backup-postgres.sh")"
python3 "$SCRIPT_DIR/fingerprint.py" "$POSTGRES_CONTAINER" "$POSTGRES_USER" "$POSTGRES_DB" > "$TEMP_DIR/before.json"
"$SCRIPT_DIR/restore-postgres-test.sh" "$BACKUP_FILE"
"$SCRIPT_DIR/check-restore.sh"
python3 "$SCRIPT_DIR/fingerprint.py" "$POSTGRES_CONTAINER" "$POSTGRES_USER" "$RESTORE_DB" > "$TEMP_DIR/after.json"
python3 - "$TEMP_DIR/before.json" "$TEMP_DIR/after.json" <<'PYCODE'
import json, sys
a, b = [json.load(open(p)) for p in sys.argv[1:]]
if not a or a != b:
    sys.exit("ERROR: restored row counts/data fingerprints differ from source")
print(f"Restore data comparison: PASS ({len(a)} tables; counts and fingerprints identical)")
PYCODE
docker start "$GATEWAY_CONTAINER" >/dev/null
restart_needed=false
echo "BACKUP / RESTORE DRILL: PASS"
echo "Backup: $BACKUP_FILE"
