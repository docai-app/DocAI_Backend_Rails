#!/usr/bin/env python3
"""Independent host watchdog. Never changes schedules, queues or submissions.

Default read-only. --notify uses existing Rails SMTP directly (not Redis) with a
private on-disk six-hour send-attempt cooldown. SMTP uncertainty is not retried.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

CONTAINERS = ('aienglish-operations-reports', 'docai_backend_rails-docai-rails-1')


def command(container, notify=False):
    return ['docker', 'exec', '-i', '-e', 'RUBYOPT=-W0', container, 'bundle', 'exec',
            'rails', 'runner', '-e', 'production', 'ops/reliability/schedule_health.rb'] + (['--notify'] if notify else [])


def issue_codes(health):
    codes = list(health.get('issues', []))
    for role in health.get('roles', []):
        codes.extend(role['role'] + ':' + code for code in role['issues'])
    return sorted(set(codes)) or ([] if health.get('healthy') else ['health_check_unavailable'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notify', action='store_true')
    parser.add_argument('--state-dir', type=Path)
    args = parser.parse_args()
    live = subprocess.check_output(['docker', 'ps', '--format', '{{.Names}}'], text=True).splitlines()
    container = next((name for name in CONTAINERS if name in live), None)
    health = {'healthy': False, 'issues': ['health_check_unavailable']}
    if container:
        try:
            result = subprocess.run(command(container), capture_output=True, text=True, timeout=90, check=True)
            line = next(line for line in result.stdout.splitlines() if line.startswith('SCHEDULE_HEALTH='))
            health = json.loads(line.split('=', 1)[1])
        except (subprocess.SubprocessError, StopIteration, ValueError):
            pass  # Never print raw Rails output, environment, or exception payloads.
    codes = issue_codes(health)
    print(json.dumps({'healthy': not codes, 'issues': codes}))
    if not codes or not args.notify:
        return 0 if not codes else 1
    if args.state_dir is None or not args.state_dir.is_dir():
        raise ValueError('A private existing state directory is required')
    folder = args.state_dir
    if folder.is_symlink() or folder.stat().st_uid != os.getuid() or folder.stat().st_mode & 0o077:
        raise ValueError('State directory must be private and operator-owned')
    fd = os.open(folder / 'watchdog.json', os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(fd, 'r+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        raw = stream.read()
        state = json.loads(raw) if raw else {}
        now = time.time()
        if now - state.get('attempted_at', 0) < 6 * 3600:
            print('Alert cooldown active; review previous SMTP result in journal.')
            return 1
        if not container:
            print('No Rails container available for SMTP; host alert remains failed.')
            return 1
        # Persist before transmission, including ambiguous/failed transmission.
        stream.seek(0)
        stream.truncate()
        json.dump({'attempted_at': now, 'issues': codes}, stream)
        stream.flush()
        os.fsync(stream.fileno())
        try:
            result = subprocess.run(command(container, True), input=json.dumps(codes), capture_output=True, text=True, timeout=90)
            accepted = result.returncode == 0 and 'SMTP_ACCEPTED' in result.stdout.splitlines()
        except subprocess.SubprocessError:
            accepted = False
        print('SMTP accepted health alert; verify inbox separately.' if accepted else
              'Health alert delivery unconfirmed; investigate before retrying.')
    return 1  # An alert does not make infrastructure healthy.


if __name__ == '__main__':
    raise SystemExit(main())
