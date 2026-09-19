#!/usr/bin/env python3
"""Contain published Redis without restarting it or touching keys/queues.

Run as root after reviewing clients. Dry-run by default. Rules affect only TCP
6379 arriving on the explicitly selected public interface; Docker peers survive.
Does not alter SSH, flush firewall rules, or enable Redis password validation.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone


def capture(command):
    return subprocess.check_output(command, text=True).strip()


def rules(interface):
    if not re.fullmatch(r'[a-zA-Z0-9_.:-]{1,32}', interface):
        raise ValueError('Invalid interface')
    return [
        ('DOCKER-USER', ['-i', interface, '-p', 'tcp', '-m', 'conntrack',
                         '--ctorigdstport', '6379', '-m', 'comment',
                         '--comment', 'aienglish-redis-ingress', '-j', 'DROP']),
        ('INPUT', ['-i', interface, '-p', 'tcp', '--dport', '6379', '-m',
                   'comment', '--comment', 'aienglish-redis-ingress', '-j', 'DROP']),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interface', required=True)
    parser.add_argument('--evidence-dir', type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--remove', action='store_true', help='Remove only these exact rules (explicit rollback)')
    args = parser.parse_args()
    plan = rules(args.interface)
    if not Path('/sys/class/net', args.interface).exists():
        raise ValueError('Interface does not exist')
    if args.remove and not args.apply:
        raise ValueError('Rollback requires --apply')
    # Inspect chains before changing anything. IPv6 Docker may use only the
    # docker-proxy/INPUT path and have no DOCKER-USER chain.
    targets = []
    for binary in ('iptables', 'ip6tables'):
        for chain, rule in plan:
            result = subprocess.run([binary, '-w', '5', '-S', chain], capture_output=True, text=True)
            if result.returncode and not (binary == 'ip6tables' and chain == 'DOCKER-USER'):
                raise RuntimeError('Cannot inspect ' + binary + ' ' + chain)
            if not result.returncode:
                targets.append((binary, chain, rule))
    print(json.dumps({'apply': args.apply, 'remove': args.remove, 'interface': args.interface,
                      'targets': [b + ':' + c for b, c, _ in targets]}))
    if not args.apply:
        return
    if os.geteuid() != 0:
        raise ValueError('Root required')
    if not args.remove:
        if args.evidence_dir is None:
            raise ValueError('Private evidence directory required')
        folder = args.evidence_dir.resolve()
        folder.mkdir(mode=0o700, parents=False, exist_ok=False)
        os.chmod(folder, 0o700)
        def save(name, content):
            fd = os.open(folder / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w') as stream:
                stream.write(content + '\n')
        save('time.txt', datetime.now(timezone.utc).isoformat())
        save('iptables.txt', capture(['iptables-save']))
        save('ip6tables.txt', capture(['ip6tables-save']))
        container = 'docai_backend_rails-redis-1'
        info = json.loads(capture(['docker', 'inspect', container]))[0]
        save('redis-container.json', json.dumps({key: info[key] for key in
             ('Id', 'Created', 'State', 'Mounts', 'NetworkSettings')}, indent=2))
        for name, command in [('redis-info.txt', ['INFO']), ('redis-clients.txt', ['CLIENT', 'LIST'])]:
            save(name, capture(['docker', 'exec', container, 'redis-cli'] + command))
        log = subprocess.run(['docker', 'logs', '--tail', '1000', container], capture_output=True, text=True, check=True)
        save('redis-log.txt', log.stdout + log.stderr)
    for binary, chain, rule in targets:
        exists = subprocess.run([binary, '-w', '5', '-C', chain] + rule, capture_output=True).returncode == 0
        if args.remove and exists:
            subprocess.run([binary, '-w', '5', '-D', chain] + rule, check=True)
        elif not args.remove and not exists:
            subprocess.run([binary, '-w', '5', '-I', chain, '1'] + rule, check=True)
    print('Exact ingress rules applied. No containers, keys, queues or credentials changed.')


if __name__ == '__main__':
    main()
