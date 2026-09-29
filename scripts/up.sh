#!/usr/bin/env bash

set -euo pipefail

if [ ! -f .env ]; then
    echo ".env not found"
    echo "Run: cp .env.example .env"
    exit 1
fi

docker compose up -d

echo
echo "Services started."
echo "LiteLLM: http://localhost:4000"