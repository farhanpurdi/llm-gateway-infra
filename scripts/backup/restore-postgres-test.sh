#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/restore-target.sh"
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <backup.dump>" >&2
  exit 1
fi
"$SCRIPT_DIR/verify-backup.sh" "$1"
# Check the backup's identity before touching the dedicated test database.
python3 - "$1.json" "$POSTGRES_DB" <<'PYCODE'
import json, sys
if json.load(open(sys.argv[1]))["database"] != sys.argv[2]:
    sys.exit("ERROR: backup belongs to a different source database")
PYCODE
docker exec "$POSTGRES_CONTAINER" dropdb -U "$POSTGRES_USER" --if-exists "$RESTORE_DB"
docker exec "$POSTGRES_CONTAINER" createdb -U "$POSTGRES_USER" "$RESTORE_DB"
docker exec -i "$POSTGRES_CONTAINER" pg_restore \
  -U "$POSTGRES_USER" -d "$RESTORE_DB" --exit-on-error --no-owner --no-acl < "$1"
echo "Restore completed into dedicated test database: $RESTORE_DB"
