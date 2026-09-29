#!/usr/bin/env bash

set -euo pipefail

read -p "Delete local containers and volumes? [y/N] " answer

if [ "$answer" != "y" ]; then
    exit 0
fi

docker compose down -v