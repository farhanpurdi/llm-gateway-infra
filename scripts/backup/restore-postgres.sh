#!/usr/bin/env bash
# Compatibility entrypoint: this script restores ONLY the dedicated test DB.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/restore-postgres-test.sh" "$@"
