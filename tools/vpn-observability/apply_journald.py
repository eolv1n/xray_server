#!/usr/bin/env python3
"""Install the VPN journal limit on one host, keeping rollback data on cp-01."""
import datetime
import os
from pathlib import Path
import subprocess
import sys

from collect import HOSTS

PATH = '/etc/systemd/journald.conf.d/99-infrastek-vpn.conf'
CONFIG = Path(__file__).with_name('journald-vpn.conf').read_bytes()


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {h[0] for h in HOSTS}:
        raise SystemExit('usage: apply_journald.py baloonz_ru|baloonz_eu|silnet')
    role = sys.argv[1]
    _, _, target, options = next(h for h in HOSTS if h[0] == role)
    base = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6', *options, target]

    def run(*args, data=None, check=True):
        return subprocess.run(base + list(args), input=data, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, check=check, timeout=30)

    run('sudo', '-n', 'true')
    previous = run('sudo', '-n', 'cat', PATH, check=False)
    if previous.returncode and run('sudo', '-n', 'test', '!', '-e', PATH, check=False).returncode:
        raise RuntimeError('Cannot determine previous configuration')
    backup = Path.home() / '.local/state/vpn-observability/backups' / (role + '-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup, 0o700)
    (backup / ('previous.conf' if previous.returncode == 0 else 'previous-absent')).write_bytes(previous.stdout if previous.returncode == 0 else b'')
    os.chmod(next(backup.iterdir()), 0o600)
    try:
        run('sudo', '-n', 'install', '-D', '-m', '0644', '/dev/stdin', PATH, data=CONFIG)
        run('sudo', '-n', 'systemctl', 'restart', 'systemd-journald')
        run('sudo', '-n', 'systemctl', 'is-active', '--quiet', 'systemd-journald')
    except (OSError, subprocess.SubprocessError):
        if previous.returncode == 0:
            run('sudo', '-n', 'install', '-D', '-m', '0644', '/dev/stdin', PATH, data=previous.stdout, check=False)
        else:
            run('sudo', '-n', 'rm', '-f', PATH, check=False)
        run('sudo', '-n', 'systemctl', 'restart', 'systemd-journald', check=False)
        raise
    print('configured:', role, 'backup:', backup)
    # Rotation and vacuum remove only archived journal files. A very recent
    # file can be removed by the size limit if 250 MiB is insufficient.
    run('sudo', '-n', 'journalctl', '--rotate')
    run('sudo', '-n', 'journalctl', '--vacuum-time=2days', '--vacuum-size=250M')
    usage = run('sudo', '-n', 'journalctl', '--disk-usage').stdout.decode().strip()
    print('journal:', usage)


if __name__ == '__main__':
    main()
