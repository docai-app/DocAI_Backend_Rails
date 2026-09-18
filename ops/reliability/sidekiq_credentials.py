#!/usr/bin/env python3
"""Provision independent Sidekiq credentials on the server; never print secrets.

Only appends previously absent Sidekiq keys to the existing Rails .env. Rails
loads this with dotenv on boot. Does not change ADMIN_TOKEN or restart services.
The operator must restart only Rails web and test authenticated/anonymous paths.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import tempfile
from worker_runtime import capture, private_write


def provision(repo, runtime, sha, apply=False):
    repo, runtime = repo.resolve(), runtime.resolve()
    if runtime == repo or repo in runtime.parents:
        raise ValueError('Credentials must be outside Git')
    if capture(['git', '-C', str(repo), 'rev-parse', 'HEAD']) != sha:
        raise ValueError('Unexpected checkout SHA')
    env_path = repo / '.env'
    if env_path.is_symlink() or not env_path.is_file() or env_path.stat().st_uid != os.getuid():
        raise ValueError('Expected a regular operator-owned dotenv file')
    previous = env_path.read_text()
    if re.search(r'^\s*(?:export\s+)?SIDEKIQ_ADMIN_(?:USER|PASSWORD)\s*=', previous, re.M):
        raise ValueError('Credentials already configured; do not silently rotate')
    if not apply:
        print('Ready to append independent Sidekiq credentials; ADMIN_TOKEN is unchanged.')
        return
    runtime.mkdir(mode=0o700, parents=False, exist_ok=True)
    if runtime.stat().st_uid != os.getuid() or runtime.stat().st_mode & 0o077:
        raise ValueError('Runtime directory must be private and owned by operator')
    credentials = {'username': 'aienglish-operations', 'password': secrets.token_hex(32)}
    private_write(runtime / 'sidekiq-credentials.private.json', json.dumps(credentials) + '\n')
    private_write(runtime / 'before-sidekiq.env.private', previous)
    updated = previous.rstrip('\n') + '\n\n# Independent Sidekiq Web credentials (server-only).\n'
    updated += 'SIDEKIQ_ADMIN_USER=' + credentials['username'] + '\n'
    updated += 'SIDEKIQ_ADMIN_PASSWORD=' + credentials['password'] + '\n'
    fd, temporary = tempfile.mkstemp(prefix='.sidekiq-env-', dir=str(repo))
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        # Only replace the exact baseline inspected above; no concurrent changes lost.
        if env_path.read_text() != previous:
            raise ValueError('dotenv changed concurrently; refuse overwrite')
        os.replace(temporary, env_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('Independent Sidekiq credentials saved privately. Restart web only, then verify. No secrets printed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime-dir', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    provision(args.repo, args.runtime_dir, args.sha, args.apply)
