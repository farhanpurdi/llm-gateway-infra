#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: $0 <non-empty-backup.dump>" >&2
  exit 1
fi
python3 - "$1" <<'PYCODE'
import hashlib, json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    data = json.loads(Path(str(p) + ".json").read_text())
    for file, field in ((p, "sha256"), (Path(str(p) + ".env"), "environment_sha256")):
        if hashlib.sha256(file.read_bytes()).hexdigest() != data[field]:
            sys.exit("ERROR: backup checksum mismatch")
except (OSError, ValueError, KeyError):
    sys.exit("ERROR: backup metadata or protected environment is missing/invalid")
print("Backup checksums: PASS")
PYCODE
docker exec -i "$POSTGRES_CONTAINER" pg_restore --list < "$1" > /dev/null
echo "Backup archive readable: PASS"
