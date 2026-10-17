#!/usr/bin/env bash
# Source after common.sh. Never allow the active database as a restore-test target.
required_env POSTGRES_DB
required_env POSTGRES_USER
RESTORE_DB="${RESTORE_DB:-${POSTGRES_DB}_restore_test}"
if [ "${#RESTORE_DB}" -gt 63 ] || \
   [[ ! "$RESTORE_DB" =~ ^[a-zA-Z0-9_]+$ ]] || \
   [ "$RESTORE_DB" != "${POSTGRES_DB}_restore_test" ] || \
   [ "$RESTORE_DB" = "$POSTGRES_DB" ]; then
  echo "ERROR: restore target must be the dedicated <POSTGRES_DB>_restore_test database." >&2
  exit 1
fi
export RESTORE_DB
