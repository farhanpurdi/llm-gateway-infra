#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd
)"

REPO_ROOT="$(
  cd "$SCRIPT_DIR/../.." &&
  pwd
)"

cd "$REPO_ROOT"

echo
echo "======================================"
echo "LLM Gateway Infra Validation"
echo "======================================"

echo
echo "[1/7] Bash syntax"

while IFS= read -r -d '' file; do
  echo "Checking: $file"
  bash -n "$file"
done < <(
  find scripts \
    -type f \
    -name "*.sh" \
    -print0
)

echo "Bash syntax: PASS"


echo
echo "[2/7] ShellCheck"

if ! command -v shellcheck >/dev/null; then
  echo "ERROR: shellcheck is not installed."
  exit 1
fi

find scripts \
  -type f \
  -name "*.sh" \
  -print0 \
  | xargs -0 shellcheck \
      --severity=warning

echo "ShellCheck: PASS"


echo
echo "[3/7] Environment template"

python3 \
  scripts/ci/validate-env-example.py


echo
echo "[4/7] Base Docker Compose"

LITELLM_CONFIG_PATH="$REPO_ROOT/.github/fixtures/litellm_config.yaml"
export LITELLM_CONFIG_PATH

docker compose \
  config \
  --quiet

docker compose \
  config \
  --format json \
  | python3 scripts/ci/validate-compose.py base -


echo
echo "[5/7] Development override"

docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  config \
  --quiet

docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  config \
  --format json \
  | python3 scripts/ci/validate-compose.py dev -


echo
echo "[6/7] Operational regression tests"

python3 scripts/ci/test-operations.py

echo
echo "[7/7] Git safety"

if git ls-files \
    | grep -qE '(^|/)\.env$'; then

    echo "ERROR: .env is tracked by Git."
    exit 1
fi

if git ls-files \
    | grep -qE '\.(dump|sql)$'; then

    echo "ERROR: database backup "
    echo "is tracked by Git."
    exit 1
fi


echo
echo "======================================"
echo "INFRA VALIDATION: PASSED"
echo "======================================"
