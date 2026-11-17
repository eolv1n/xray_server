#!/usr/bin/env python3
"""Collect bounded VPN metrics on cp-01; no historical files on VPN hosts."""
import grp
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

BASE = Path(__file__).resolve().parent
REMOTE = BASE / 'remote_sample.py'
OUTPUT = Path('/backup/current/catalog/vpn-observability.prom')
KNOWN = Path.home() / '.local/state/vpn-observability/ovh-known-hosts'
HOSTS = (
    ('baloonz_ru', 'baloonz', 'baloonz-ru', ()),
    ('baloonz_eu', 'baloonz', 'ubuntu@10.243.95.2',
     ('-J', 'baloonz-ru', '-o', 'HostKeyAlias=57.129.152.73',
      '-o', f'UserKnownHostsFile={KNOWN}', '-o', 'StrictHostKeyChecking=yes')),
    ('silnet', 'silnet', 'silnetbridge', ()),
)


def esc(value):
    return str(value).replace('\\', '\\\\').replace('\n', '\\n').replace('"', '\\"')


def metric(name, value, **labels):
    number = float(value)
    if not math.isfinite(number):
        raise ValueError('invalid metric')
    attrs = ','.join(f'{key}="{esc(value)}"' for key, value in sorted(labels.items()))
    return f'{name}{{{attrs}}} {number:.17g}'


def render(samples, now):
    result = []
    for role, project, _target, _options in HOSTS:
        data = samples.get(role)
        labels = {'node': role, 'project': project}
        result.append(metric('vpn_observer_success', bool(data), **labels))
        result.append(metric('vpn_observer_attempt_timestamp_seconds', now, **labels))
        if not data:
            continue
        for key, name in (
            ('cpu_total', 'vpn_node_cpu_seconds_total'), ('cpu_idle', 'vpn_node_cpu_idle_seconds_total'),
            ('memory_total', 'vpn_node_memory_bytes'), ('memory_available', 'vpn_node_memory_available_bytes'),
            ('swap_total', 'vpn_node_swap_bytes'), ('swap_free', 'vpn_node_swap_free_bytes'),
            ('uptime', 'vpn_node_uptime_seconds'),
            ('disk_total', 'vpn_node_disk_bytes'), ('disk_available', 'vpn_node_disk_available_bytes'),
            ('inodes_total', 'vpn_node_inodes'), ('inodes_available', 'vpn_node_inodes_available'),
        ):
            result.append(metric(name, data[key], **labels))
        for name, state in sorted(data.get('services', {}).items()):
            result.append(metric('vpn_service_healthy', state, service=name, **labels))
        for key, prefix in (('network', 'vpn_node_network'), ('wireguard', 'vpn_wireguard')):
            network = data.get(key)
            if not network:
                continue
            for field in ('rx_bytes', 'tx_bytes', 'rx_errors', 'tx_errors', 'rx_dropped', 'tx_dropped'):
                result.append(metric(f'{prefix}_{field}_total', network[field], **labels))
            if key == 'wireguard':
                result.append(metric('vpn_wireguard_handshake_timestamp_seconds', network['latest_handshake'], **labels))
        if role in ('baloonz_ru', 'silnet'):
            result.append(metric('vpn_profile_observation_success', data.get('profiles_ok', False), **labels))
            if not data.get('profiles_ok'):
                continue
            if role == 'baloonz_ru':
                result.append(metric('vpn_profiles_missing_identifier', data.get('profiles_missing_identifier', 0), **labels))
            for profile in data.get('profiles', []):
                profile_labels = dict(labels, profile_id=profile['key'], profile=profile['name'][:128])
                if role == 'baloonz_ru':
                    for field, direction in (('up', 'up'), ('down', 'down')):
                        result.append(metric('vpn_profile_traffic_bytes_total', profile[field],
                                             direction=direction, **profile_labels))
                else:
                    result.append(metric('vpn_profile_traffic_bytes_total', profile['total'],
                                         direction='combined', **profile_labels))
    names = sorted({line.split('{', 1)[0].split(' ', 1)[0] for line in result})
    headers = []
    for name in names:
        headers.extend((f'# HELP {name} VPN infrastructure observation.',
                        f'# TYPE {name} {"counter" if name.endswith("_total") else "gauge"}'))
    return '\n'.join(headers + result) + '\n'


def collect_one(target, options, role, remote):
    args = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6', '-o', 'IPQoS=none',
            '-o', 'ServerAliveInterval=4', '-o', 'ServerAliveCountMax=1', *options,
            target, 'python3', '-', role]
    completed = subprocess.run(args, input=remote, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=16, check=True)
    if len(completed.stdout) > 1024 * 1024:
        raise ValueError('sample too large')
    return json.loads(completed.stdout)


def atomic_publish(content):
    # Prometheus node_exporter runs as nobody. Restrict local access to the
    # owner and that group; labels are not printed to stdout or logs.
    output_dir = OUTPUT.parent
    fd, path = tempfile.mkstemp(prefix='.vpn-observability-', dir=output_dir)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(content)
        gid = grp.getgrnam('nogroup').gr_gid
        subprocess.run(['sudo', '-n', 'chgrp', str(gid), path], check=True,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.chmod(path, 0o640)
        os.replace(path, OUTPUT)
    finally:
        if os.path.exists(path):
            os.unlink(path)


def main():
    remote = REMOTE.read_bytes()
    samples = {}
    for role, _project, target, options in HOSTS:
        try:
            samples[role] = collect_one(target, options, role, remote)
        except (OSError, ValueError, subprocess.SubprocessError):
            samples[role] = None
            print(f'{role}: sample unavailable', file=sys.stderr)
    atomic_publish(render(samples, time.time()))
    return 0 if all(samples.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
