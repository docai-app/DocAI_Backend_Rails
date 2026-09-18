import importlib.util
from datetime import datetime, timezone, timedelta
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('worker_runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTest(unittest.TestCase):
    def source(self):
        return {'Id': 'source-id', 'Image': 'sha256:image', 'State': {'Status': 'running'},
                'Config': {'Entrypoint': None, 'WorkingDir': '/docai-rails', 'User': '',
                           'Cmd': ['bundle', 'exec', 'sidekiq', '-e', 'production'],
                           'Env': ['RAILS_ENV=production', 'REDIS_URL=redis://redis:6379/0']},
                'Mounts': [{'Type': 'bind', 'Source': '/tmp/runtime-repo', 'Destination': '/docai-rails'}],
                'NetworkSettings': {'Networks': {'existing-app': {}}}}

    def test_validate_expected_source(self):
        network, env = runtime.validate_source(self.source(), Path('/tmp/runtime-repo').resolve(), 'a' * 40)
        self.assertEqual(network, 'existing-app')
        self.assertEqual(env['RAILS_ENV'], 'production')

    def test_fail_closed_for_changed_source(self):
        for change in ['stopped', 'entrypoint', 'mount', 'network', 'environment', 'cmd']:
            with self.subTest(change=change):
                s = self.source()
                if change == 'stopped': s['State']['Status'] = 'exited'
                if change == 'entrypoint': s['Config']['Entrypoint'] = ['migrate']
                if change == 'mount': s['Mounts'].append(s['Mounts'][0])
                if change == 'network': s['NetworkSettings']['Networks']['second'] = {}
                if change == 'environment': s['Config']['Env'][0] = 'RAILS_ENV=development'
                if change == 'cmd': s['Config']['Cmd'].append('-q')
                with self.assertRaises(ValueError):
                    runtime.validate_source(s, Path('/tmp/runtime-repo').resolve(), 'a' * 40)

    def test_role_isolation_and_activation(self):
        now = datetime(2026, 9, 18, 12, 1, tzinfo=timezone(timedelta(hours=8)))
        stale = {'AI_ENGLISH_REPORTS_ENABLED_AT': 'old', 'AI_ENGLISH_RECOVERY_ENABLED_AT': 'old'}
        for role in ['reports', 'recovery']:
            env = runtime.role_env(stale, role, now, 'test@example.test')
            self.assertEqual(env['ADMIN_NOTIFICATION_EMAIL'], 'test@example.test')
            self.assertEqual(env['AI_ENGLISH_REPORT_WORKER'], str(role == 'reports').lower())
            self.assertEqual(env['AI_ENGLISH_RECOVERY_WORKER'], str(role == 'recovery').lower())
            dates = [v for k, v in env.items() if k.endswith('ENABLED_AT')]
            self.assertEqual(dates, [now.isoformat(timespec='seconds')])

    def test_no_backdate_input_or_wrong_zone(self):
        with self.assertRaises(ValueError):
            runtime.role_env({}, 'recovery', datetime.now(timezone.utc), 'test@example.test')

    def test_no_recipient_injection(self):
        with self.assertRaises(ValueError):
            runtime.role_env({}, 'reports', datetime.now(timezone(timedelta(hours=8))), 'a@b\nSECRET=x')

    def test_command_preserves_source_and_has_no_port_or_grading_queue(self):
        args = runtime.create_args('test', self.source(), 'existing-app', Path('/private/reports.env'), 'reports', 'a' * 40)
        self.assertIn('source-id', args)
        self.assertIn('sha256:image', args)
        self.assertIn('config/sidekiq_operations_reports.yml', args)
        self.assertNotIn('-p', args)
        self.assertNotIn('default', args)
        self.assertNotIn('db:migrate', args)
        self.assertIn('--restart', args)

    def test_private_write_never_overwrites_activation(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / 'runtime.env'
            runtime.private_write(f, 'value')
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError): runtime.private_write(f, 'overwrite')
            self.assertEqual(f.read_text(), 'value')


if __name__ == '__main__':
    unittest.main()
