#!/usr/bin/env python3

from pathlib import Path
import sys


ENV_FILE = Path(".env.example")

REQUIRED_KEYS = {
    "LITELLM_BASE_URL",
    "LITELLM_MASTER_KEY",
    "LITELLM_SALT_KEY",

    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "DATABASE_URL",

    "REDIS_HOST",
    "REDIS_PORT",
    "REDIS_PASSWORD",

    "OPENAI_API_KEY",

    "LLM_GATEWAY_CONFIG_DIR",
    "LITELLM_CONFIG_PATH",

    "HEALTHCHECK_API_KEY",
}


def fail(message: str) -> None:
    print(
        f"ERROR: {message}",
        file=sys.stderr,
    )
    sys.exit(1)


if not ENV_FILE.exists():
    fail(".env.example not found")


keys = set()

for raw_line in ENV_FILE.read_text(
    encoding="utf-8"
).splitlines():

    line = raw_line.strip()

    if not line:
        continue

    if line.startswith("#"):
        continue

    if "=" not in line:
        fail(
            f"Invalid .env.example line: "
            f"{raw_line}"
        )

    key, _ = line.split("=", 1)

    key = key.strip()

    if not key:
        fail(
            f"Empty environment variable name: "
            f"{raw_line}"
        )

    if key in keys:
        fail(
            f"Duplicate environment variable: "
            f"{key}"
        )

    keys.add(key)


missing = REQUIRED_KEYS - keys

if missing:
    fail(
        "Missing required environment variable(s): "
        + ", ".join(sorted(missing))
    )


print(
    f".env.example contains "
    f"{len(keys)} variable(s)"
)

print(".env.example validation: PASS")