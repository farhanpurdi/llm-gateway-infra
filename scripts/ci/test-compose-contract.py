#!/usr/bin/env python3
"""Regression for Compose JSON serializers that omit explicitly false bind options."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


VALIDATOR = Path(__file__).with_name("validate-compose.py")


class ConfigBindContractTests(unittest.TestCase):
    def check_contract(self, *, normalized=None, declared=None, expected=0):
        mount = {"type": "bind", "target": "/app/config.yaml", "read_only": True,
                 "bind": {"create_host_path": False}}
        source_mount = copy.deepcopy(mount)
        if normalized is not None:
            mount = normalized
        if declared is None:
            declared = [source_mount]
        services = {name: {"networks": {"llm-backend": {}}}
                    for name in ("postgres", "redis", "litellm")}
        services["litellm"].update(ports=[{"target": 4000, "published": "4000"}], volumes=[mount])
        source = {"services": {"litellm": {"volumes": declared}}}
        with tempfile.TemporaryDirectory(prefix="compose-contract-") as directory:
            path = Path(directory) / "source.yaml"
            path.write_text(yaml.safe_dump(source))
            result = subprocess.run([sys.executable, str(VALIDATOR), "base", "-", str(path)],
                                    input=json.dumps({"services": services}), capture_output=True,
                                    text=True, timeout=10, check=False)
        self.assertEqual(result.returncode, expected, result.stderr)
        if expected:
            self.assertIn("create_host_path=false", result.stderr)

    def mount(self, **updates):
        return {"type": "bind", "target": "/app/config.yaml", "read_only": True, **updates}

    def test_explicit_normalized_false_is_accepted(self):
        self.check_contract()

    def test_omitted_normalized_bind_is_accepted_with_explicit_source_false(self):
        self.check_contract(normalized=self.mount())

    def test_empty_normalized_bind_is_accepted_with_explicit_source_false(self):
        self.check_contract(normalized=self.mount(bind={}))

    def test_normalized_true_or_null_is_rejected(self):
        for value in (True, None):
            with self.subTest(value=value):
                self.check_contract(normalized=self.mount(bind={"create_host_path": value}), expected=1)

    def test_explicit_source_true_is_rejected(self):
        self.check_contract(normalized=self.mount(),
                            declared=[self.mount(bind={"create_host_path": True})], expected=1)

    def test_omitted_source_option_is_rejected(self):
        self.check_contract(normalized=self.mount(), declared=[self.mount()], expected=1)

    def test_short_source_syntax_is_rejected(self):
        self.check_contract(declared=["./config.yaml:/app/config.yaml:ro"], expected=1)

    def test_duplicate_source_mount_is_rejected(self):
        mount = self.mount(bind={"create_host_path": False})
        self.check_contract(declared=[mount, copy.deepcopy(mount)], expected=1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
