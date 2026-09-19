#!/usr/bin/env python3
"""Disposable local Redis test only; hardcoded container/name/loopback port."""
import json
import os
import subprocess
import unittest
import time
from redis_auth_runtime import acl_rules, APP_DENY, protocol

NAME = 'aienglish-redis-acl-local-test'


class RedisAclLiveTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(['docker', 'run', '-d', '--name', NAME, '-p', '127.0.0.1:56391:6379',
                        'redis:7-alpine', 'redis-server', '--save', '', '--appendonly', 'no'], check=True, capture_output=True)
        for _ in range(25):
            ready = subprocess.run(['docker', 'exec', NAME, 'redis-cli', 'PING'], capture_output=True)
            if ready.stdout.strip() == b'PONG':
                return
            time.sleep(0.2)
        raise RuntimeError('Local test Redis failed to become ready')

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['docker', 'rm', '-f', NAME], check=True, capture_output=True)

    def cli(self, *args):
        return subprocess.check_output(['docker', 'exec', NAME, 'redis-cli'] + list(args), text=True).strip()

    def test_clients_authenticate_and_cannot_flush(self):
        payload = protocol([['ACL', 'SETUSER', 'fixture'] + acl_rules('a' * 64) + APP_DENY])
        result = subprocess.run(['docker', 'exec', '-i', NAME, 'redis-cli', '--pipe'], input=payload, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(b'errors: 0,', result.stdout)
        self.assertEqual('OK', self.cli('SET', 'protected-fixture', 'keep'))
        # ACL DRYRUN evaluates permissions without executing a destructive command.
        self.assertIn('no permissions', self.cli('ACL', 'DRYRUN', 'fixture', 'FLUSHALL'))
        self.assertIn('no permissions', self.cli('ACL', 'DRYRUN', 'fixture', 'FLUSHDB'))
        self.assertEqual('OK', self.cli('ACL', 'DRYRUN', 'fixture', 'EVAL', 'return 1', '0'))
        self.assertEqual('OK', self.cli('ACL', 'SETUSER', 'default', 'off'))
        self.assertIn('NOAUTH', self.cli('PING'))
        auth = ['--user', 'fixture', '-a', 'a' * 64, '--no-auth-warning']
        self.assertEqual('PONG', self.cli(*auth, 'PING'))
        self.assertEqual('keep', self.cli(*auth, 'GET', 'protected-fixture'))
        self.assertEqual('1', self.cli(*auth, 'LPUSH', 'queue:fixture', 'job'))
        self.assertEqual('job', self.cli(*auth, 'BRPOP', 'queue:fixture', '1').splitlines()[-1])
        self.assertEqual('1', self.cli(*auth, 'EVAL', 'return 1', '0'))
        env = dict(os.environ, RELIABILITY_TEST_REDIS_URL='redis://fixture:' + 'a' * 64 + '@127.0.0.1:56391/0')
        subprocess.run(['bundle', 'exec', 'ruby', 'ops/reliability/scheduler_coexistence_test.rb'], env=env, check=True)
        # Restore ONLY this disposable fixture's default user using a separate
        # operator for scheduler integration is deliberately not needed here.


if __name__ == '__main__':
    unittest.main()
