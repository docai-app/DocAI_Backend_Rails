import unittest
from redis_auth_runtime import acl_rules, protocol, APP_DENY


class RedisAuthTest(unittest.TestCase):
    def test_password_is_hashed_and_application_cannot_clear_queue(self):
        rules = acl_rules('private-fixture') + APP_DENY
        self.assertNotIn('private-fixture', ' '.join(rules))
        self.assertEqual(len(rules[2]), 65)
        for forbidden in ['-flushall', '-flushdb', '-config', '-acl']:
            self.assertIn(forbidden, rules)

    def test_resp_uses_byte_lengths_and_separate_commands(self):
        self.assertEqual(protocol([['PING'], ['ECHO', 'é']]), b'*1\r\n$4\r\nPING\r\n*2\r\n$4\r\nECHO\r\n$2\r\n\xc3\xa9\r\n')


if __name__ == '__main__':
    unittest.main()
