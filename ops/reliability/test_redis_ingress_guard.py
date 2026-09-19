import unittest
from redis_ingress_guard import rules


class RedisIngressGuardTest(unittest.TestCase):
    def test_only_external_redis_ingress(self):
        plan = rules('eth0')
        self.assertEqual(['DOCKER-USER', 'INPUT'], [chain for chain, _ in plan])
        for _, rule in plan:
            self.assertEqual(['-i', 'eth0'], rule[:2])
            self.assertIn('6379', rule)
            self.assertEqual(['-j', 'DROP'], rule[-2:])
            self.assertNotIn('22', rule)

    def test_invalid_interfaces(self):
        for value in ('', '../eth0', 'eth0;reboot', 'eth0\n', '-i eth0'):
            with self.assertRaises(ValueError):
                rules(value)


if __name__ == '__main__':
    unittest.main()
