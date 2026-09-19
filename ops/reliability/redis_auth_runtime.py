#!/usr/bin/env python3
"""Reviewed AI English Redis ACL rollout; never FLUSH, delete volumes, or migrate.

prepare: generate private credentials, add named ACL users, persist ACL file and
patch private compose/.env. Existing default access stays until cutover.
cutover: requires all four application containers stopped after operator drain;
save/backup Redis RDB, replace only Redis on the SAME volume, no public ports.
Dry-run unless --apply. Existing runtime files are preserved, never regenerated.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

REDIS = 'docai_backend_rails-redis-1'
WEB = 'docai_backend_rails-docai-rails-1'
CLIENTS = (WEB, 'docai_backend_rails-sidekiq-1', 'aienglish-operations-reports', 'aienglish-generation-recovery')
APP_DENY = ['-flushall', '-flushdb', '-swapdb', '-config', '-acl', '-shutdown', '-replicaof', '-slaveof', '-debug', '-module', '-migrate']


def capture(args, **kwargs):
    result = subprocess.run(args, capture_output=True, check=False, **kwargs)
    if result.returncode:
        raise RuntimeError('Operational command failed; inspect private runtime and container status')
    return result.stdout


def private_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data if isinstance(data, bytes) else data.encode())


def acl_rules(password):
    return ['on', 'resetpass', '#' + hashlib.sha256(password.encode()).hexdigest(), '~*', '&*', '+@all']


def protocol(commands):
    result = b''
    for command in commands:
        result += ('*%d\r\n' % len(command)).encode()
        for arg in command:
            data = str(arg).encode()
            result += ('$%d\r\n' % len(data)).encode() + data + b'\r\n'
    return result


def pipe(commands):
    output = capture(['docker', 'exec', '-i', REDIS, 'redis-cli', '--pipe'], input=protocol(commands))
    if b'errors: 0,' not in output:
        raise RuntimeError('Redis ACL command rejected; do not continue')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['prepare', 'cutover'])
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime-dir', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    repo, folder = args.repo.resolve(), args.runtime_dir.resolve()
    if repo == folder or repo in folder.parents:
        raise ValueError('Runtime must be outside Git checkout')
    if capture(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip() != args.sha:
        raise ValueError('Approved SHA does not match checkout')
    capture(['git', '-C', str(repo), 'diff', '--exit-code', '--quiet', 'HEAD'])
    for private in ('.env', 'docker-compose.yml'):
        capture(['git', '-C', str(repo), 'check-ignore', '-q', private])
    redis = json.loads(capture(['docker', 'inspect', REDIS]))[0]
    networks = list(redis['NetworkSettings']['Networks'])
    mounts = redis['Mounts']
    if len(networks) != 1 or networks[0] != 'docai_backend_rails_default' or len(mounts) != 1 or mounts[0].get('Name') != 'docai_backend_rails_redis-data' or mounts[0]['Destination'] != '/data':
        raise ValueError('Unexpected Redis topology; review manually')
    print(json.dumps({'stage': args.stage, 'apply': args.apply, 'sha': args.sha,
                      'redis_image': redis['Image'], 'volume': mounts[0]['Name'], 'public_ports_after_cutover': []}))
    if not args.apply:
        return
    if args.stage == 'prepare':
        folder.mkdir(mode=0o700, parents=False, exist_ok=False)
        original_env = (repo / '.env').read_text()
        if any(line.startswith(('AI_ENGLISH_REDIS_USERNAME=', 'AI_ENGLISH_REDIS_PASSWORD=')) for line in original_env.splitlines()):
            raise ValueError('Authentication already configured; do not overwrite')
        compose_path = repo / 'docker-compose.yml'
        original_compose = compose_path.read_bytes()
        # Reuse installed Ruby YAML parser; no host dependency installation.
        parsed = capture(['docker', 'exec', '-i', WEB, 'ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.safe_load(STDIN.read, aliases: true))'], input=original_compose)
        compose = json.loads(parsed)
        service = compose['services']['redis']
        if service.get('command') not in ('redis-server --save 60 1 --loglevel warning', ['redis-server', '--save', '60', '1', '--loglevel', 'warning']):
            raise ValueError('Redis command differs; review before changing')
        private_write(folder / 'original.env', original_env)
        private_write(folder / 'original-compose.yml', original_compose)
        private_write(folder / 'original-redis.json', json.dumps(redis))
        credentials = {'app': secrets.token_hex(32), 'operator': secrets.token_hex(32)}
        private_write(folder / 'credentials.private.json', json.dumps(credentials))
        app_rules = acl_rules(credentials['app']) + APP_DENY
        operator_rules = acl_rules(credentials['operator'])
        acl = 'user default off resetpass -@all\nuser aienglish ' + ' '.join(app_rules) + '\nuser aienglish_operator ' + ' '.join(operator_rules) + '\n'
        private_write(folder / 'users.acl', acl)
        pipe([['ACL', 'SETUSER', 'aienglish'] + app_rules,
              ['ACL', 'SETUSER', 'aienglish_operator'] + operator_rules])
        capture(['docker', 'cp', str(folder / 'users.acl'), REDIS + ':/data/aienglish-users.acl'])
        capture(['docker', 'exec', REDIS, 'chown', 'redis:redis', '/data/aienglish-users.acl'])
        # No secret in command arguments or stdout. Preserve all existing entries.
        with (repo / '.env').open('a') as stream:
            stream.write('\nAI_ENGLISH_REDIS_USERNAME=aienglish\nAI_ENGLISH_REDIS_PASSWORD=' + credentials['app'] + '\n')
        service['command'] = ['redis-server', '--save', '60', '1', '--loglevel', 'warning', '--aclfile', '/data/aienglish-users.acl', '--protected-mode', 'yes']
        service.pop('ports', None)
        # JSON is valid YAML, avoiding dumping secrets via shell or terminal.
        compose_path.write_text(json.dumps(compose, indent=2) + '\n')
        os.chmod(repo / '.env', 0o600)
        os.chmod(compose_path, 0o600)
        print('Prepared named users, private credentials and restart configuration. Default access remains until Redis cutover. Restart clients only after safe drain.')
    else:
        if not folder.is_dir() or folder.stat().st_mode & 0o077 or folder.stat().st_uid != os.getuid():
            raise ValueError('Private prepared runtime directory required')
        clients = json.loads(capture(['docker', 'inspect'] + list(CLIENTS)))
        if any(c['State']['Running'] for c in clients):
            raise ValueError('All scoped clients must be stopped after draining before Redis replacement')
        if (folder / 'cutover.json').exists():
            raise ValueError('Cutover already attempted; inspect before retry')
        # Verify expected named identities exist before taking the snapshot.
        users = capture(['docker', 'exec', REDIS, 'redis-cli', 'ACL', 'USERS']).decode().splitlines()
        if not {'aienglish', 'aienglish_operator'}.issubset(users):
            raise ValueError('Named users not prepared')
        answer = capture(['docker', 'exec', REDIS, 'redis-cli', 'SAVE']).decode().strip()
        if answer != 'OK':
            raise RuntimeError('Redis snapshot failed; do not replace container')
        capture(['docker', 'cp', REDIS + ':/data/dump.rdb', str(folder / 'redis-before-cutover.rdb')])
        backup = folder / 'redis-before-cutover.rdb'
        os.chmod(backup, 0o600)
        if backup.stat().st_size < 10:
            raise ValueError('Redis backup invalid')
        private_write(folder / 'redis.env', '\n'.join(redis['Config']['Env']) + '\n')
        old_name = REDIS + '-pre-auth-' + args.sha[:7]
        command = ['docker', 'create', '--name', REDIS, '--restart', redis['HostConfig']['RestartPolicy']['Name'],
                   '--network', networks[0], '--network-alias', 'redis', '--mount', 'type=volume,src=' + mounts[0]['Name'] + ',dst=/data',
                   '--env-file', str(folder / 'redis.env')]
        for key, value in redis['Config']['Labels'].items():
            command += ['--label', key + '=' + value]
        command += [redis['Image'], 'redis-server', '--save', '60', '1', '--loglevel', 'warning', '--aclfile', '/data/aienglish-users.acl', '--protected-mode', 'yes']
        private_write(folder / 'cutover.json', json.dumps({'sha': args.sha, 'old_name': old_name, 'backup_bytes': backup.stat().st_size, 'at': time.time()}))
        capture(['docker', 'stop', '--timeout', '60', REDIS])
        # A manually stopped restart=always container can revive after Docker
        # restarts. The retained rollback container must never share the volume
        # with the new running Redis.
        capture(['docker', 'update', '--restart', 'no', REDIS])
        capture(['docker', 'rename', REDIS, old_name])
        capture(command)
        capture(['docker', 'start', REDIS])
        print('Redis replaced on existing volume; no public port. Verify unauthenticated denial and authenticated clients before resuming workers. Old stopped container retained, never start it alongside the new Redis.')


if __name__ == '__main__':
    main()
