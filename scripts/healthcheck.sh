#!/usr/bin/env bash

set -euo pipefail

echo "Checking LiteLLM..."

curl --fail \
    http://localhost:4000/health/liveliness

echo
echo "LiteLLM is alive."