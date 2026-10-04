#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    print(
        f"ERROR: {message}",
        file=sys.stderr,
    )
    sys.exit(1)


if len(sys.argv) != 3:
    fail(
        "Usage: "
        "validate-compose.py "
        "<base|dev> <compose-json>"
    )


mode = sys.argv[1]
compose_file = Path(sys.argv[2])


if mode not in {
    "base",
    "dev",
}:
    fail(
        "mode must be 'base' or 'dev'"
    )


if not compose_file.exists():
    fail(
        f"Compose JSON not found: "
        f"{compose_file}"
    )


with compose_file.open(
    encoding="utf-8"
) as f:
    compose = json.load(f)


services = compose.get(
    "services",
    {}
)


required_services = {
    "litellm",
    "postgres",
    "redis",
}


missing_services = (
    required_services
    - set(services)
)

if missing_services:
    fail(
        "Missing service(s): "
        + ", ".join(
            sorted(missing_services)
        )
    )


def ports(
    service_name: str,
) -> list[dict[str, Any]]:

    value = (
        services
        .get(service_name, {})
        .get("ports", [])
    )

    return value or []


def networks(
    service_name: str,
) -> set[str]:

    value = (
        services
        .get(service_name, {})
        .get("networks", {})
    )

    if isinstance(value, dict):
        return set(value)

    if isinstance(value, list):
        return set(value)

    return set()


#
# All services must be connected to
# the private backend network.
#

for service_name in required_services:

    service_networks = networks(
        service_name
    )

    if "llm-backend" not in service_networks:
        fail(
            f"{service_name} is not connected "
            "to llm-backend"
        )


#
# LiteLLM must publish port 4000.
#

litellm_ports = ports("litellm")

has_litellm_4000 = any(
    int(port.get("target", 0)) == 4000
    and str(
        port.get("published", "")
    ) == "4000"
    for port in litellm_ports
)

if not has_litellm_4000:
    fail(
        "LiteLLM must publish port 4000"
    )


#
# LiteLLM config mount must be read-only.
#

litellm_volumes = (
    services["litellm"]
    .get("volumes", [])
    or []
)

config_mount = None

for volume in litellm_volumes:

    if not isinstance(volume, dict):
        continue

    if (
        volume.get("target")
        == "/app/config.yaml"
    ):
        config_mount = volume
        break


if config_mount is None:
    fail(
        "LiteLLM config volume "
        "is not mounted at /app/config.yaml"
    )


if not config_mount.get(
    "read_only",
    False,
):
    fail(
        "LiteLLM config mount "
        "must be read-only"
    )


#
# Base compose:
#
# Postgres / Redis may be exposed
# internally, but must NOT be
# published to the host.
#

if mode == "base":

    if ports("postgres"):
        fail(
            "PostgreSQL must not publish "
            "a host port in base compose"
        )

    if ports("redis"):
        fail(
            "Redis must not publish "
            "a host port in base compose"
        )


#
# Development override:
#
# Host ports are allowed, but only
# through 127.0.0.1.
#

if mode == "dev":

    expected = {
        "postgres": 5432,
        "redis": 6379,
    }

    for service_name, expected_port \
            in expected.items():

        service_ports = ports(
            service_name
        )

        matching = [
            port
            for port in service_ports
            if int(
                port.get(
                    "target",
                    0,
                )
            ) == expected_port
        ]

        if not matching:
            fail(
                f"{service_name} must publish "
                f"{expected_port} in dev mode"
            )

        for port in matching:

            host_ip = port.get(
                "host_ip"
            )

            if host_ip != "127.0.0.1":
                fail(
                    f"{service_name} dev port "
                    "must bind to 127.0.0.1, "
                    f"got: {host_ip!r}"
                )


print(
    f"Docker Compose "
    f"{mode} validation: PASS"
)