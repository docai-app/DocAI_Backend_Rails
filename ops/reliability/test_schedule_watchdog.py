import unittest
from schedule_watchdog import issue_codes, command


class WatchdogTest(unittest.TestCase):
    def test_registry_loss_is_not_a_healthy_worker(self):
        self.assertEqual(issue_codes({'healthy': False, 'roles': [
            {'role': 'recovery', 'issues': ['schedule_missing_or_invalid']}]}),
            ['recovery:schedule_missing_or_invalid'])

    def test_missing_health_fails_closed(self):
        self.assertEqual(issue_codes({}), ['health_check_unavailable'])
        self.assertEqual(issue_codes({'healthy': True, 'roles': []}), [])

    def test_notification_is_opt_in_and_uses_existing_rails(self):
        self.assertNotIn('--notify', command('fixture'))
        self.assertEqual(command('fixture', True)[-1], '--notify')


if __name__ == '__main__':
    unittest.main()
