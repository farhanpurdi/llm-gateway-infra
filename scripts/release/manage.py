#!/usr/bin/env python3
"""Config releases on the SAME existing container. Never creates containers."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import yaml

ROOT = Path(__file__).resolve().parents[2]
RELEASES = ROOT / 'releases'


class UniqueKeyLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        keys = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                if key in keys:
                    raise ValueError('Duplicate YAML mapping key')
                keys.add(key)
            except TypeError as exc:
                raise ValueError('YAML mapping keys must be scalar values') from exc
        return super().construct_mapping(node, deep=deep)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def release_dir(name):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', name):
        raise ValueError('Invalid release ID')
    path = RELEASES / name
    if path.is_symlink():
        raise ValueError('Release directory must not be a symlink')
    return path


def runtime():
    names = [os.environ.get(key, default) for key, default in (
        ('GATEWAY_CONTAINER', 'llm-gateway'),
        ('POSTGRES_CONTAINER', 'llm-gateway-postgres'),
        ('REDIS_CONTAINER', 'llm-gateway-redis'))]
    info = json.loads(run('docker', 'inspect', *names, capture_output=True).stdout)
    if not all(item['State']['Running'] for item in info):
        raise ValueError('All three existing containers must be running')
    gateway = info[0]
    mounts = [m for m in gateway['Mounts'] if m['Destination'] == '/app/config.yaml']
    if len(mounts) != 1 or mounts[0]['Type'] != 'bind' or mounts[0]['RW']:
        raise ValueError('Expected a read-only config bind mount')
    source = Path(mounts[0]['Source'])
    expected = Path(os.environ['LLM_GATEWAY_CONFIG_DIR']) / 'config/litellm_config.yaml'
    if source.resolve() != expected.resolve() or not source.is_file():
        raise ValueError('Config mount differs from the configured repository')
    if os.environ['LITELLM_BASE_URL'].rstrip('/') not in (
        'http://localhost:4000', 'http://127.0.0.1:4000'):
        raise ValueError('This procedure is limited to the existing local port 4000')
    ports = gateway['NetworkSettings']['Ports'].get('4000/tcp') or []
    if not any(p['HostPort'] == '4000' for p in ports):
        raise ValueError('Existing gateway is not published on port 4000')
    return {
        'containers': {n: {'id': c['Id'], 'image_id': c['Image'],
                            'image_tag': c['Config']['Image']} for n, c in zip(names, info)},
        'config_path': str(source), 'gateway': names[0],
    }


def validate_config(data):
    try:
        config = yaml.load(data, Loader=UniqueKeyLoader)
    except yaml.YAMLError as exc:
        raise ValueError('Release config contains invalid YAML') from exc
    if not isinstance(config, dict):
        raise ValueError('Config must be a mapping')
    expected = {'company-fast': 'openai/gpt-5.6-terra',
                'company-coding': 'openai/gpt-5.6-sol'}
    models = config.get('model_list')
    if not isinstance(models, list) or any(not isinstance(m, dict) for m in models):
        raise ValueError('model_list must be a list of mappings')
    names = [m.get('model_name') for m in models]
    if (any(not isinstance(name, str) for name in names)
            or len(names) != len(set(names)) or set(names) != set(expected)):
        raise ValueError('Expected exactly two unique approved logical aliases')
    for model in models:
        params = model.get('litellm_params')
        if not isinstance(params, dict):
            raise ValueError('litellm_params must be a mapping')
        if params.get('model') != expected[model['model_name']]:
            raise ValueError('Upstream model differs from the approved Phase 1 contract')
        if params.get('api_key') != 'os.environ/OPENAI_API_KEY':
            raise ValueError('Provider key must reference os.environ/OPENAI_API_KEY')
        if params.get('custom_llm_provider', 'openai') != 'openai':
            raise ValueError('Provider override is not approved')
        if any(field in params for field in ('api_base', 'base_url', 'api_type')):
            raise ValueError('Endpoint/type override requires an approved contract')
    general = config.get('general_settings')
    if not isinstance(general, dict):
        raise ValueError('general_settings must be a mapping')
    for key, value in {'master_key': 'os.environ/LITELLM_MASTER_KEY',
                       'database_url': 'os.environ/DATABASE_URL'}.items():
        if general.get(key) != value:
            raise ValueError(f'{key} must reference {value}')
    overrides = ('fallbacks', 'default_fallbacks', 'context_window_fallbacks',
                 'content_policy_fallbacks', 'model_group_alias', 'default_model')
    settings = [('config', config)] + [(key, config[key]) for key in
        ('litellm_settings', 'router_settings', 'general_settings') if key in config]
    for location, value in settings:
        if not isinstance(value, dict):
            raise ValueError(f'{location} must be a mapping')
        if any(field in value and value[field] not in (None, [], {}) for field in overrides):
            raise ValueError('Alternate routing is not approved in Phase 1')


def revisions():
    result = {}
    for repo in ('llm-gateway-infra', 'llm-gateway-config', 'llm-gateway-e2e'):
        path = ROOT.parent / repo
        head = run('git', '-C', str(path), 'rev-parse', 'HEAD', capture_output=True).stdout.strip()
        status = run('git', '-C', str(path), 'status', '--porcelain', capture_output=True).stdout
        paths = run('git', '-C', str(path), 'ls-files', '-c', '-o', '--exclude-standard', '-z',
                    capture_output=True).stdout.split('\0')
        files = {name: digest((path / name).read_bytes()) for name in sorted(set(paths))
                 if name and (path / name).is_file()}
        result[repo] = {'head': head, 'dirty': bool(status), 'source_sha256': files}
    return result


def capture(name, config=None):
    state = runtime()
    data = Path(config or state['config_path']).read_bytes()
    validate_config(data)
    path = release_dir(name)
    path.mkdir(mode=0o700)  # Never overwrite an existing release.
    (path / 'config.yaml').write_bytes(data)
    manifest = {**state, 'created_at': datetime.now(timezone.utc).isoformat(),
                'config_sha256': digest(data), 'repositories': revisions()}
    (path / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Captured release: {name}')


def load_release(name, state):
    path = release_dir(name)
    manifest = json.loads((path / 'manifest.json').read_text())
    data = (path / 'config.yaml').read_bytes()
    if digest(data) != manifest['config_sha256']:
        raise ValueError('Release checksum mismatch')
    for key in ('containers', 'config_path', 'gateway'):
        if manifest[key] != state[key]:
            raise ValueError(f'Runtime changed ({key}); config-only rollback is unsafe')
    validate_config(data)
    return data


def write_config(path, data):
    # Write the existing inode: atomic rename would leave a file bind mount stale.
    with Path(path).open('r+b') as stream:
        stream.write(data)
        stream.truncate()
        stream.flush()
        os.fsync(stream.fileno())


def verify(state, data):
    deadline = time.monotonic() + 120
    while True:
        result = subprocess.run([str(ROOT / 'scripts/health/readiness.sh')],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError('Gateway readiness timed out')
        time.sleep(2)
    mounted = subprocess.check_output(['docker', 'exec', state['gateway'], 'cat', '/app/config.yaml'])
    if digest(mounted) != digest(data):
        raise ValueError('Container is reading a stale config mount')
    run(str(ROOT / 'scripts/health/check-all.sh'))
    env = dict(os.environ, E2E_ENV_FILE=os.environ['ENV_FILE'])
    run(str(ROOT.parent / 'llm-gateway-e2e/scripts/run-smoke.sh'), env=env)


def apply_release(name):
    state = runtime()
    data = load_release(name, state)
    original = Path(state['config_path']).read_bytes()
    backup = run(str(ROOT / 'scripts/backup/backup-postgres.sh'), capture_output=True).stdout.strip()
    record = {'release': name, 'started_at': datetime.now(timezone.utc).isoformat(),
              'before_sha256': digest(original), 'target_sha256': digest(data), 'backup': backup}
    operation = RELEASES / ('operation-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f') + '.json')
    # Save recovery bytes BEFORE the first write; these survive a killed process.
    recovery = operation.with_suffix('.config.yaml')
    recovery.write_bytes(original)
    record.update(status='in_progress', recovery_config=str(recovery))
    operation.write_text(json.dumps(record, indent=2) + '\n')
    try:
        write_config(state['config_path'], data)
        run('docker', 'restart', state['gateway'], stdout=subprocess.DEVNULL)
        verify(state, data)
        if runtime() != state:
            raise ValueError('Container identity changed during release')
        record['status'] = 'passed'
    except BaseException:
        record['status'] = 'failed'
        try:
            write_config(state['config_path'], original)
            run('docker', 'restart', state['gateway'], stdout=subprocess.DEVNULL)
            verify(state, original)
            record['recovery'] = 'passed'
        except BaseException:
            record['recovery'] = 'failed; use saved recovery config and backup'
        raise
    finally:
        operation.write_text(json.dumps(record, indent=2) + '\n')
    print(f'Release verification: PASS ({name}); same container IDs/images')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    capture_parser = sub.add_parser('capture')
    capture_parser.add_argument('name')
    capture_parser.add_argument('--config')
    for command in ('deploy', 'rollback'):
        sub.add_parser(command).add_argument('name')
    args = parser.parse_args()
    os.umask(0o077)
    RELEASES.mkdir(mode=0o700, exist_ok=True)
    with (RELEASES / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == 'capture':
            capture(args.name, args.config)
        else:
            apply_release(args.name)


if __name__ == '__main__':
    main()
