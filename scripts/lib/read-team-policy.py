#!/usr/bin/env python3

import json
import sys
from pathlib import Path

import yaml


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


if len(sys.argv) != 2:
    fail("Usage: read-team-policy.py <policy-file>")

policy_file = Path(sys.argv[1])

if not policy_file.exists():
    fail(f"Policy file not found: {policy_file}")

with policy_file.open("r", encoding="utf-8") as f:
    policy = yaml.safe_load(f)

if not isinstance(policy, dict):
    fail("Policy must contain a YAML object")

required_top_level = [
    "name",
    "models",
    "limits",
]

for field in required_top_level:
    if field not in policy:
        fail(f"Missing required field: {field}")

if not isinstance(policy["models"], list) or not policy["models"]:
    fail("'models' must contain at least one model")

limits = policy["limits"]

if "team" not in limits:
    fail("Missing limits.team")

if "member" not in limits:
    fail("Missing limits.member")

team_limits = limits["team"]
member_limits = limits["member"]

required_team_limits = [
    "monthly_budget_usd",
    "rpm",
    "tpm",
]

for field in required_team_limits:
    if field not in team_limits:
        fail(f"Missing limits.team.{field}")

if "monthly_budget_usd" not in member_limits:
    fail("Missing limits.member.monthly_budget_usd")

print(json.dumps(policy))