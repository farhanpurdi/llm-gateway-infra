#!/usr/bin/env bash

set -euo pipefail

read -r -p \
  "Delete local containers and volumes? [y/N] " \
  answer

case "$answer" in
  y|Y|yes|YES)
    docker compose down -v
    ;;
  *)
    echo "Cancelled."
    ;;
esac