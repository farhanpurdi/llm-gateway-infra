#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/restore-target.sh"
COUNT="$(docker exec "$POSTGRES_CONTAINER" psql -X -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d "$RESTORE_DB" -tAc \
  "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public'")"
if [ "$COUNT" -eq 0 ]; then
  echo "ERROR: restored database has no public tables" >&2
  exit 1
fi
echo "Restore verification: PASS ($COUNT public tables)"
