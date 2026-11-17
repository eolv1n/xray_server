import importlib.util
from pathlib import Path
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect.py'))
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)
REMOTE_SPEC = importlib.util.spec_from_file_location('remote_sample', Path(__file__).with_name('remote_sample.py'))
remote = importlib.util.module_from_spec(REMOTE_SPEC)
REMOTE_SPEC.loader.exec_module(remote)


def host(profiles):
    return dict(cpu_total=100, cpu_idle=50, memory_total=1000, memory_available=500,
                swap_total=0, swap_free=0, uptime=100,
                disk_total=100, disk_available=20, inodes_total=20, inodes_available=10,
                services={'xray': True}, profiles_ok=True, profiles=profiles)


class CollectionTests(unittest.TestCase):
    @mock.patch.object(remote.subprocess, 'run')
    def test_missing_container_is_unhealthy_without_losing_host(self, run):
        run.return_value.stdout = '/amnezia-xray\ttrue\tnone\n'
        run.return_value.returncode = 1
        self.assertEqual(remote.read_services('baloonz_ru'), {'amnezia-xray': True, 'wg-easy': False})

    def test_failed_host_is_explicit_and_never_emits_stale_data(self):
        sample = host([{'key': 'a', 'name': 'тест', 'up': 42, 'down': 7}])
        output = collector.render({'baloonz_ru': sample, 'baloonz_eu': None}, 1794456123)
        self.assertIn('vpn_observer_success{node="baloonz_eu",project="baloonz"} 0', output)
        self.assertIn('vpn_observer_attempt_timestamp_seconds{node="baloonz_ru",project="baloonz"} 1794456123', output)
        self.assertNotIn('vpn_node_disk_bytes{node="baloonz_eu"', output)

    def test_profiles_have_stable_id_and_are_safely_escaped(self):
        sample = host([{'key': '1234', 'name': 'name"\\\n', 'up': 2, 'down': 3}])
        output = collector.render({'baloonz_ru': sample}, 10)
        self.assertIn('profile_id="1234"', output)
        self.assertIn('profile="name\\"\\\\\\n"', output)
        self.assertIn('direction="up"', output)

    def test_silnet_combined_bytes_and_missing_profile_data(self):
        silnet = host([{'key': 'a', 'name': 'alice', 'total': 1000000}])
        ru = host([])
        ru['profiles_ok'] = False
        output = collector.render({'baloonz_ru': ru, 'silnet': silnet}, 10)
        self.assertIn('direction="combined"', output)
        self.assertIn('vpn_profile_observation_success{node="baloonz_ru",project="baloonz"} 0', output)
        self.assertNotIn('vpn_profile_traffic_bytes_total{direction="up"', output)


if __name__ == '__main__':
    unittest.main()
