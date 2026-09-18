#!/usr/bin/env python3
"""Start ONLY an approved dedicated worker using the existing Rails image/runtime.

Dry run by default. No migrations, source updates, image pulls, queue deletion,
main worker restart, or backdated activation. Keep runtime_dir outside Git.
"""
import argparse
from datetime import datetime, timezone, timedelta
import json
import os
from pathlib import Path
import subprocess

ROLES = {
    'reports': ('AI_ENGLISH_REPORT', 'operations_reports'),
    'recovery': ('AI_ENGLISH_RECOVERY', 'generation_recovery'),
}


def capture(args):
    return subprocess.check_output(args, text=True).strip()


def validate_source(source, repo, sha):
    if source['State']['Status'] != 'running':
        raise ValueError('Source worker is not running')
    config = source['Config']
    if config['Entrypoint'] or config['WorkingDir'] != '/docai-rails':
        raise ValueError('Unexpected entrypoint/working directory')
    if config['Cmd'] != ['bundle', 'exec', 'sidekiq', '-e', 'production']:
        raise ValueError('Not the approved production main worker')
    if config.get('User') not in ('', 'root', None):
        raise ValueError('Unexpected container user; review runtime first')
    mounts = source['Mounts']
    if len(mounts) != 1 or mounts[0]['Type'] != 'bind' or Path(mounts[0]['Source']).resolve() != repo or mounts[0]['Destination'] != '/docai-rails':
        raise ValueError('Unexpected source mounts')
    networks = list(source['NetworkSettings']['Networks'])
    if len(networks) != 1 or networks[0] in ('host', 'none', 'bridge'):
        raise ValueError('Expected one existing application network')
    env = dict(item.split('=', 1) for item in config['Env'])
    if env.get('RAILS_ENV') != 'production' or not env.get('REDIS_URL'):
        raise ValueError('Source runtime is not production or lacks Redis')
    if any('\n' in value or '\r' in value for value in env.values()):
        raise ValueError('Multiline environment values require manual review')
    if not source['Image'].startswith('sha256:') or len(sha) != 40 or any(c not in '0123456789abcdef' for c in sha):
        raise ValueError('An exact source image and Git SHA are required')
    return networks[0], env


def role_env(base, role, now, recipient):
    if now.utcoffset() != timedelta(hours=8):
        raise ValueError('Use Macau activation time')
    if not recipient or any(c.isspace() for c in recipient) or recipient.count('@') != 1:
        raise ValueError('One explicit recipient is required')
    env = base.copy()
    env.update(AI_ENGLISH_REPORT_WORKER='false', AI_ENGLISH_REPORTS_ENABLED='false',
               AI_ENGLISH_RECOVERY_WORKER='false', AI_ENGLISH_RECOVERY_ENABLED='false')
    env.pop('AI_ENGLISH_REPORTS_ENABLED_AT', None)
    env.pop('AI_ENGLISH_RECOVERY_ENABLED_AT', None)
    stamp = now.isoformat(timespec='seconds')
    if role == 'reports':
        env.update(AI_ENGLISH_REPORT_WORKER='true', AI_ENGLISH_REPORTS_ENABLED='true', AI_ENGLISH_REPORTS_ENABLED_AT=stamp)
    elif role == 'recovery':
        env.update(AI_ENGLISH_RECOVERY_WORKER='true', AI_ENGLISH_RECOVERY_ENABLED='true', AI_ENGLISH_RECOVERY_ENABLED_AT=stamp)
    else:
        raise ValueError('Unknown role')
    env['ADMIN_NOTIFICATION_EMAIL'] = recipient
    return env


def create_args(name, source, network, env_file, role, sha):
    queue = ROLES[role][1]
    return ['docker', 'create', '--name', name, '--restart', 'always',
            '--cpus', '1', '--memory', '1536m', '--memory-swap', '1536m',
            '--log-driver', 'json-file', '--log-opt', 'max-size=10m', '--log-opt', 'max-file=3',
            '--stop-timeout', '180', '--network', network, '--volumes-from', source['Id'],
            '--env-file', str(env_file), '--workdir', '/docai-rails',
            '--label', 'aienglish.role=' + role, '--label', 'aienglish.release=' + sha,
            source['Image'], 'bundle', 'exec', 'sidekiq', '-e', 'production',
            '-C', 'config/sidekiq_' + queue + '.yml']


def private_write(filename, content):
    fd = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('role', choices=ROLES)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--runtime-dir', required=True, type=Path)
    parser.add_argument('--recipient', required=True)
    parser.add_argument('--source', default='docai_backend_rails-sidekiq-1')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    repo = args.repo.resolve()
    runtime = args.runtime_dir.resolve()
    if runtime == repo or repo in runtime.parents or runtime.is_symlink():
        raise ValueError('Runtime secrets must be outside the checkout')
    if capture(['git', '-C', str(repo), 'rev-parse', 'HEAD']) != args.sha:
        raise ValueError('Checkout does not match approved SHA')
    subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', '--quiet', 'HEAD'], check=True)
    source = json.loads(capture(['docker', 'inspect', args.source]))[0]
    network, base = validate_source(source, repo, args.sha)
    name = 'aienglish-' + ROLES[args.role][1].replace('_', '-')
    if name in capture(['docker', 'ps', '-a', '--format', '{{.Names}}']).splitlines():
        raise ValueError('Dedicated container already exists; inspect it, do not duplicate/reset activation')
    env = role_env(base, args.role, datetime.now(timezone(timedelta(hours=8))), args.recipient)
    env_file = runtime / (args.role + '.env')
    command = create_args(name, source, network, env_file, args.role, args.sha)
    print(json.dumps({'apply': args.apply, 'name': name, 'role': args.role, 'sha': args.sha,
                      'image': source['Image'], 'network': network, 'queue': ROLES[args.role][1],
                      'activation': env.get('AI_ENGLISH_REPORTS_ENABLED_AT') or env.get('AI_ENGLISH_RECOVERY_ENABLED_AT')}))
    if not args.apply:
        return
    runtime.mkdir(mode=0o700, parents=False, exist_ok=True)
    if runtime.stat().st_uid != os.getuid() or runtime.stat().st_mode & 0o077:
        raise ValueError('Runtime directory must be private and owned by operator')
    private_write(env_file, ''.join(k + '=' + v + '\n' for k, v in sorted(env.items())))
    private_write(runtime / (args.role + '.manifest.json'), json.dumps({
        'name': name, 'sha': args.sha, 'source_id': source['Id'], 'image': source['Image'],
        'command': command, 'activation': env.get('AI_ENGLISH_REPORTS_ENABLED_AT') or env.get('AI_ENGLISH_RECOVERY_ENABLED_AT')}, indent=2) + '\n')
    container_id = capture(command)
    # If starting fails, preserve the stopped container and files for diagnosis.
    subprocess.run(['docker', 'start', container_id], check=True)
    print('Created dedicated worker. Verify startup, two scheduler ticks and actual delivery separately.')


if __name__ == '__main__':
    main()
