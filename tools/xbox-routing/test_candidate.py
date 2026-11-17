import json
from pathlib import Path
import subprocess
import unittest

FILTER = Path(__file__).with_name('candidate.jq')
SOURCES = ['192.168.1.85/32', '192.168.1.150/32']


def generate(config):
    return subprocess.run(['jq', '--argjson', 'sources', json.dumps(SOURCES), '-f', str(FILTER)],
                          input=json.dumps(config), text=True, capture_output=True)


class RoutingTests(unittest.TestCase):
    def test_insert_before_existing_xbox_bypass_without_changing_other_rules(self):
        before = {'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': [
            {'port': '22', 'outboundTag': 'direct'},
            {'domain': ['domain:xbox.com', 'domain:xboxlive.com'], 'outboundTag': 'direct'},
            {'outboundTag': 'vless-reality-test'}]}}
        result = generate(before)
        self.assertEqual(result.returncode, 0, result.stderr)
        rules = json.loads(result.stdout)['routing']['rules']
        self.assertEqual([rules[0], *rules[3:]], before['routing']['rules'])
        self.assertEqual([r['outboundTag'] for r in rules[1:3]], ['direct', 'vless-reality-test'])
        self.assertTrue(all(r['source'] == SOURCES for r in rules[1:3]))
        self.assertIn('domain:delivery.mp.microsoft.com', rules[1]['domain'])
        self.assertIn('domain:xboxlive.com', rules[2]['domain'])
        self.assertNotEqual(generate(json.loads(result.stdout)).returncode, 0)

    def test_missing_or_ambiguous_anchor_is_rejected(self):
        for rules in ([], [{'domain': ['domain:xbox.com']}] * 2):
            self.assertNotEqual(generate({'routing': {'rules': rules}}).returncode, 0)


if __name__ == '__main__':
    unittest.main()
