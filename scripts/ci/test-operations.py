#!/usr/bin/env python3
"""Offline failure-path checks; Docker and the real .env are never used."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_manager', ROOT / 'scripts/release/manage.py')
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
CONFIG = b'''model_list:
- model_name: company-fast
  litellm_params: {model: openai/gpt-5.6-terra, api_key: os.environ/OPENAI_API_KEY}
- model_name: company-coding
  litellm_params: {model: openai/gpt-5.6-sol, api_key: os.environ/OPENAI_API_KEY}
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
'''


class Operations(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.envfile = self.path / '.env'
        self.envfile.write_text(f'LITELLM_BASE_URL=http://localhost:4000\nLITELLM_MASTER_KEY=test-only\n'
                                f'POSTGRES_DB=litellm\nPOSTGRES_USER=litellm\nLLM_GATEWAY_CONFIG_DIR={ROOT}\n')
        binary = self.path / 'docker'
        binary.write_text('#!/bin/sh\necho UNEXPECTED_DOCKER >&2\nexit 99\n')
        binary.chmod(0o700)
        self.env = dict(os.environ, LLM_GATEWAY_ENV_FILE=str(self.envfile),
                        PATH=f'{self.path}:{os.environ["PATH"]}')
        self.release_patch = patch.object(manager, 'RELEASES', self.path / 'releases')
        self.release_patch.start()
        self.addCleanup(self.release_patch.stop)
        manager.RELEASES.mkdir()

    def shell(self, script, *args, **env):
        return subprocess.run(['bash', str(ROOT / 'scripts' / script), *args],
                              env={**self.env, **env}, text=True, capture_output=True)

    def test_main_database_restore_rejected_before_docker(self):
        for target in ('litellm', 'other', 'litellm;drop', '-bad'):
            with self.subTest(target=target):
                result = self.shell('backup/restore-postgres-test.sh', 'missing.dump', RESTORE_DB=target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('dedicated', result.stderr)
                self.assertNotIn('UNEXPECTED_DOCKER', result.stderr)

    def test_readiness_rejects_healthy_http_when_dependency_fails(self):
        curl = self.path / "curl"
        curl.write_text("#!/bin/sh\nexit 0\n")
        curl.chmod(0o700)
        result = self.shell("health/readiness.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("readiness (HTTP + dependencies): OK", result.stdout)

    def test_restore_rejects_postgres_identifier_truncation(self):
        self.envfile.write_text(self.envfile.read_text().replace("POSTGRES_DB=litellm", "POSTGRES_DB=" + "a" * 63))
        result = self.shell("backup/restore-postgres-test.sh", "missing.dump")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dedicated", result.stderr)
        self.assertNotIn("UNEXPECTED_DOCKER", result.stderr)

    def test_common_preserves_callers_script_directory(self):
        result = subprocess.run(['bash', '-c',
            f'SCRIPT_DIR=caller; source "{ROOT}/scripts/lib/common.sh"; test "$SCRIPT_DIR" = caller'],
            env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0)

    def test_onboard_requires_policy_before_creating_user(self):
        result = self.shell('onboard-developer.sh', 'test-user', 'test-team')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('team-policy-name', result.stdout)
        self.assertNotIn('unbound variable', result.stderr)

    def test_policy_scripts_preserve_team_and_member_monthly_limits(self):
        config = self.path / 'config'
        policies = config / 'policies/teams'
        policies.mkdir(parents=True)
        policy = {'name': 'pilot', 'models': ['company-fast', 'company-coding'],
                  'limits': {'team': {'monthly_budget_usd': 10, 'rpm': 30, 'tpm': 100000},
                             'member': {'monthly_budget_usd': 2}}}
        (policies / 'pilot.yaml').write_text(yaml.safe_dump(policy))
        self.envfile.write_text(self.envfile.read_text().replace(
            f'LLM_GATEWAY_CONFIG_DIR={ROOT}', f'LLM_GATEWAY_CONFIG_DIR={config}'))
        capture = self.path / 'request.json'
        curl = self.path / 'curl'
        curl.write_text(f'#!{__import__("sys").executable}\n'
                        'import json,sys\nfrom pathlib import Path\n'
                        f'Path({str(capture)!r}).write_text(sys.argv[sys.argv.index("-d")+1])\n'
                        'print(json.dumps({"team_id":"unit-team"}))\n')
        curl.chmod(0o700)
        cases = [
            ('teams/create-team.sh', ('pilot',), {'team_alias': 'pilot',
             'models': policy['models'], 'max_budget': 10, 'budget_duration': '30d',
             'rpm_limit': 30, 'tpm_limit': 100000}),
            ('teams/add-member.sh', ('unit-team', 'unit-user', 'pilot'),
             {'team_id': 'unit-team', 'max_budget_in_team': 2,
              'budget_duration': '30d', 'member': {'role': 'user', 'user_id': 'unit-user'}}),
        ]
        for script, args, expected in cases:
            with self.subTest(script=script):
                result = self.shell(script, *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                payload = json.loads(capture.read_text())
                self.assertEqual({field: payload.get(field) for field in expected}, expected)

    def test_corrupted_backup_rejected_before_docker(self):
        backup = self.path / 'bad.dump'
        backup.write_bytes(b'changed')
        Path(str(backup) + '.env').write_text('test')
        Path(str(backup) + '.json').write_text(json.dumps({'sha256': 'wrong', 'environment_sha256': 'wrong'}))
        result = self.shell('backup/verify-backup.sh', str(backup))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum mismatch', result.stderr)
        self.assertNotIn('UNEXPECTED_DOCKER', result.stderr)

    def test_release_rejects_path_traversal(self):
        for name in ('../outside', '.', 'a/b', ''):
            with self.assertRaises(ValueError):
                manager.release_dir(name)

    def test_release_rejects_inline_credentials(self):
        with self.assertRaises(ValueError):
            manager.validate_config(CONFIG.replace(b'os.environ/OPENAI_API_KEY', b'inline-secret'))

    def test_release_rejects_removed_alias(self):
        with self.assertRaises(ValueError):
            manager.validate_config(CONFIG.replace(b'company-coding', b'other'))

    def test_release_accepts_approved_models_with_changed_timeout(self):
        doc = yaml.safe_load(CONFIG)
        doc['model_list'][1]['litellm_params']['timeout'] = 181
        manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_wrong_upstreams_for_each_alias(self):
        for index in (0, 1):
            for upstream in ('openai/unapproved', 'anthropic/unapproved', None):
                with self.subTest(index=index, upstream=upstream):
                    doc = yaml.safe_load(CONFIG)
                    doc['model_list'][index]['litellm_params']['model'] = upstream
                    with self.assertRaises(ValueError):
                        manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_duplicate_and_extra_aliases(self):
        for name in ('company-fast', 'extra'):
            with self.subTest(name=name):
                doc = yaml.safe_load(CONFIG)
                doc['model_list'].append({'model_name': name, 'litellm_params': {
                    'model': 'openai/gpt-5.6-terra', 'api_key': 'os.environ/OPENAI_API_KEY'}})
                with self.assertRaises(ValueError):
                    manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_malformed_shapes_with_value_error(self):
        for field, value in (('model_list', None), ('model_list', ['invalid']),
                             ('general_settings', []), ('router_settings', None)):
            with self.subTest(field=field, value=value):
                doc = yaml.safe_load(CONFIG)
                doc[field] = value
                with self.assertRaises(ValueError):
                    manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_different_environment_references(self):
        for field in ('api_key', 'master_key', 'database_url'):
            with self.subTest(field=field):
                doc = yaml.safe_load(CONFIG)
                target = doc['model_list'][0]['litellm_params'] if field == 'api_key' else doc['general_settings']
                target[field] = 'os.environ/OTHER_VARIABLE'
                with self.assertRaises(ValueError):
                    manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_provider_and_endpoint_overrides(self):
        for field, value in (('custom_llm_provider', 'anthropic'),
                             ('api_base', 'https://example.invalid'),
                             ('base_url', 'https://example.invalid'), ('api_type', 'azure')):
            with self.subTest(field=field):
                doc = yaml.safe_load(CONFIG)
                doc['model_list'][0]['litellm_params'][field] = value
                with self.assertRaises(ValueError):
                    manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_alternate_routing(self):
        for location in ('litellm_settings', 'router_settings', 'general_settings'):
            for field in ('fallbacks', 'model_group_alias', 'default_model'):
                with self.subTest(location=location, field=field):
                    doc = yaml.safe_load(CONFIG)
                    doc.setdefault(location, {})[field] = 'unapproved'
                    with self.assertRaises(ValueError):
                        manager.validate_config(yaml.safe_dump(doc))

    def test_release_rejects_invalid_and_duplicate_yaml(self):
        for content in (b'[broken', b'duplicate: 1\nduplicate: 2\n' + CONFIG):
            with self.assertRaises(ValueError):
                manager.validate_config(content)

    def test_capture_rejects_wrong_contract_before_creating_artifact(self):
        config = self.path / 'invalid.yaml'
        config.write_bytes(CONFIG.replace(b'openai/gpt-5.6-terra', b'openai/unapproved'))
        with patch.object(manager, 'runtime', return_value={'config_path': str(config)}), \
             patch.object(manager, 'revisions') as revisions:
            with self.assertRaises(ValueError):
                manager.capture('invalid')
        revisions.assert_not_called()
        self.assertFalse(manager.release_dir('invalid').exists())

    def test_release_rejects_wrong_contract_even_with_matching_checksum(self):
        release = manager.release_dir('wrong-contract')
        release.mkdir()
        candidate = CONFIG.replace(b'openai/gpt-5.6-terra', b'openai/unapproved')
        state = {'containers': {}, 'config_path': '/test', 'gateway': 'gateway'}
        (release / 'config.yaml').write_bytes(candidate)
        (release / 'manifest.json').write_text(json.dumps({**state, 'config_sha256': manager.digest(candidate)}))
        with self.assertRaises(ValueError):
            manager.load_release('wrong-contract', state)

    def test_config_write_preserves_bind_mount_inode(self):
        config = self.path / 'config.yaml'
        config.write_bytes(b'original-long-config')
        inode = config.stat().st_ino
        manager.write_config(config, b'short')
        self.assertEqual(config.read_bytes(), b'short')
        self.assertEqual(inode, config.stat().st_ino)

    def test_release_checksum_and_identity_guards(self):
        release = manager.release_dir('baseline')
        release.mkdir()
        (release / 'config.yaml').write_bytes(CONFIG)
        state = {'containers': {'gateway': {'id': 'same', 'image_id': 'sha256:test'}},
                 'config_path': '/test', 'gateway': 'gateway'}
        manifest = {**state, 'config_sha256': manager.digest(CONFIG)}
        (release / 'manifest.json').write_text(json.dumps(manifest))
        self.assertEqual(manager.load_release('baseline', state), CONFIG)
        with self.assertRaises(ValueError):
            manager.load_release('baseline', {**state, 'containers': {}})
        (release / 'config.yaml').write_bytes(CONFIG + b'\n')
        with self.assertRaises(ValueError):
            manager.load_release('baseline', state)

    def test_failed_deployment_recovers_original_config_and_records_failure(self):
        config = self.path / 'config.yaml'
        config.write_bytes(CONFIG)
        candidate = CONFIG + b'# candidate\n'
        state = {'config_path': str(config), 'gateway': 'existing'}
        checks = []
        def verify(_state, data):
            checks.append(data)
            if len(checks) == 1:
                raise RuntimeError('simulated failed readiness')
        with patch.object(manager, 'runtime', return_value=state), \
             patch.object(manager, 'load_release', return_value=candidate), \
             patch.object(manager, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='backup.dump\n')), \
             patch.object(manager, 'verify', side_effect=verify):
            with self.assertRaisesRegex(RuntimeError, 'simulated'):
                manager.apply_release('candidate')
        self.assertEqual(config.read_bytes(), CONFIG)
        self.assertEqual(checks, [candidate, CONFIG])
        record = json.loads(next(manager.RELEASES.glob('operation-*.json')).read_text())
        self.assertEqual(record['status'], 'failed')
        self.assertEqual(record['recovery'], 'passed')
        self.assertEqual(Path(record['recovery_config']).read_bytes(), CONFIG)


if __name__ == '__main__':
    unittest.main(verbosity=2)
