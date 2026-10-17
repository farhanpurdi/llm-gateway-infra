#!/usr/bin/env bash
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
required_env POSTGRES_DB
required_env POSTGRES_USER
BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
BACKUP_FILE="$(mktemp "$BACKUP_DIR/litellm-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")"
export BACKUP_FILE
complete=false
cleanup() {
  if [ "$complete" != true ]; then
    rm -f "$BACKUP_FILE" "$BACKUP_FILE.json" "$BACKUP_FILE.env"
  fi
}
trap cleanup EXIT

docker exec "$POSTGRES_CONTAINER" pg_dump \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-acl > "$BACKUP_FILE"
if [ ! -s "$BACKUP_FILE" ]; then
  echo "ERROR: empty database backup" >&2
  exit 1
fi
# Preserve the salt and environment required to recover encrypted database data.
cp "$ENV_FILE" "$BACKUP_FILE.env"
chmod 600 "$BACKUP_FILE" "$BACKUP_FILE.env"
python3 - "$BACKUP_FILE" "$POSTGRES_DB" "$POSTGRES_CONTAINER" <<'PYCODE'
from datetime import datetime, timezone
import hashlib, json, sys
from pathlib import Path
p = Path(sys.argv[1])
metadata = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "database": sys.argv[2], "container": sys.argv[3],
    "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
    "environment_sha256": hashlib.sha256(Path(str(p) + ".env").read_bytes()).hexdigest(),
}
Path(str(p) + ".json").write_text(json.dumps(metadata, indent=2) + "\n")
PYCODE
complete=true
echo "Backup completed (dump + checksum + protected environment)." >&2
printf '%s\n' "$BACKUP_FILE"
