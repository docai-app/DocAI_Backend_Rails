from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sidekiq_credentials as credentials


class CredentialsTest(unittest.TestCase):
    def test_dry_run_and_provision_preserve_other_settings(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / 'repo'
            repo.mkdir()
            env = repo / '.env'
            baseline = 'ADMIN_TOKEN=test-token\nSMTP_ADDRESS=test.invalid\n'
            env.write_text(baseline)
            runtime = Path(d) / 'private'
            with patch.object(credentials, 'capture', return_value='a' * 40):
                credentials.provision(repo, runtime, 'a' * 40)
                self.assertFalse(runtime.exists())
                self.assertEqual(env.read_text(), baseline)
                credentials.provision(repo, runtime, 'a' * 40, True)
                self.assertTrue(env.read_text().startswith(baseline))
                self.assertEqual(env.stat().st_mode & 0o777, 0o600)
                self.assertEqual((runtime / 'before-sidekiq.env.private').read_text(), baseline)
                self.assertEqual((runtime / 'sidekiq-credentials.private.json').stat().st_mode & 0o777, 0o600)
                with self.assertRaises(ValueError): credentials.provision(repo, runtime, 'a' * 40, True)

    def test_cannot_store_runtime_in_repo_or_change_wrong_commit(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            with self.assertRaises(ValueError): credentials.provision(repo, repo / 'secrets', 'a' * 40)
            with patch.object(credentials, 'capture', return_value='b' * 40):
                with self.assertRaises(ValueError): credentials.provision(repo, repo.parent / 'secrets', 'a' * 40)


if __name__ == '__main__':
    unittest.main()
