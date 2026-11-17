#!/usr/bin/env python3
"""Read one VPN host sample; output data only over the existing SSH session."""
import json
import hashlib
import os
import subprocess
import sys
import time


def command(*args, timeout=8):
    return subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, text=True, timeout=timeout,
                          check=True).stdout


def sample_host(role):
    with open('/proc/stat', encoding='utf-8') as f:
        cpu = list(map(int, f.readline().split()[1:]))
    ticks = os.sysconf('SC_CLK_TCK')
    memory = {}
    with open('/proc/meminfo', encoding='utf-8') as f:
        for line in f:
            key, value = line.split(':', 1)
            if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree'):
                memory[key] = int(value.split()[0]) * 1024
    disk = os.statvfs('/')
    info = {
        'timestamp': time.time(),
        'cpu_total': sum(cpu[:8]) / ticks,
        'cpu_idle': (cpu[3] + cpu[4]) / ticks,
        'memory_total': memory['MemTotal'],
        'memory_available': memory['MemAvailable'],
        'swap_total': memory.get('SwapTotal', 0),
        'swap_free': memory.get('SwapFree', 0),
        'uptime': float(open('/proc/uptime', encoding='ascii').read().split()[0]),
        'disk_total': disk.f_blocks * disk.f_frsize,
        'disk_available': disk.f_bavail * disk.f_frsize,
        'inodes_total': disk.f_files,
        'inodes_available': disk.f_favail,
    }
    with open('/proc/net/route', encoding='utf-8') as f:
        routes = [line.split() for line in f.read().splitlines()[1:]]
    default = next((row[0] for row in routes if row[1] == '00000000' and int(row[3], 16) & 1), None)
    if default:
        info['network'] = read_network(default)
    if role in ('baloonz_ru', 'baloonz_eu'):
        try:
            info['wireguard'] = read_network('bzovhwg0')
            args = ['wg', 'show', 'bzovhwg0', 'latest-handshakes']
            if role == 'baloonz_eu':
                args.insert(0, 'sudo')
                args.insert(1, '-n')
            handshakes = [int(line.split()[-1]) for line in command(*args).splitlines() if line.strip()]
            info['wireguard']['latest_handshake'] = max(handshakes, default=0)
        except (OSError, ValueError, subprocess.SubprocessError):
            info.pop('wireguard', None)
    info['services'] = read_services(role)
    if role in ('baloonz_ru', 'silnet'):
        try:
            if role == 'baloonz_ru':
                info['profiles'], info['profiles_missing_identifier'] = baloonz_profiles()
            else:
                info['profiles'] = silnet_profiles()
            info['profiles_ok'] = True
        except (OSError, ValueError, subprocess.SubprocessError, KeyError):
            info['profiles_ok'] = False
    return info


def read_network(interface):
    path = '/sys/class/net/' + interface + '/statistics/'
    result = {}
    for key in ('rx_bytes', 'tx_bytes', 'rx_errors', 'tx_errors', 'rx_dropped', 'tx_dropped'):
        with open(path + key, encoding='ascii') as f:
            result[key] = int(f.read().strip())
    return result


def read_services(role):
    result = {}
    if role == 'baloonz_eu':
        for service in ('wg-quick@bzovhwg0', 'baloonz-ovh-wg-exit'):
            proc = subprocess.run(['systemctl', 'is-active', '--quiet', service],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=5)
            result[service] = proc.returncode == 0
        return result
    names = (['amnezia-xray', 'wg-easy'] if role == 'baloonz_ru' else
             ['remnanode', 'remnawave', 'remnawave-nginx', 'remnawave-subscription-page',
              'remnawave-db', 'remnawave-redis'])
    fmt = '{{.Name}}\t{{.State.Running}}\t{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
    # Docker reports a non-zero status if even one container is missing. Keep
    # the host metrics and mark missing containers unhealthy in that case.
    inspected = subprocess.run(['docker', 'inspect', '-f', fmt, *names],
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, timeout=8)
    result.update({name: False for name in names})
    for line in inspected.stdout.splitlines():
        name, running, health = line.split('\t')
        result[name.lstrip('/')] = running == 'true' and health in ('none', 'healthy')
    return result


def baloonz_profiles():
    def read_json(path):
        return json.loads(command('docker', 'exec', 'amnezia-xray', 'cat', path))
    table = read_json('/opt/amnezia/xray/clientsTable')
    config = read_json('/opt/amnezia/xray/server.json')
    names = {c.get('clientId'): (c.get('userData') or {}).get('clientName', '') for c in table}
    profiles = {}
    missing = 0
    for inbound in config.get('inbounds', []):
        for client in (inbound.get('settings') or {}).get('clients', []) or []:
            email = client.get('email')
            if not email:
                missing += 1
            if email and email not in ('server_key', 'alert_key'):
                key = hashlib.sha256(email.encode()).hexdigest()[:16]
                profiles[email] = {'key': key,
                                   'name': names.get(client.get('id')) or ('Профиль ' + key[:8]),
                                   'up': 0, 'down': 0}
    stats = json.loads(command('docker', 'exec', 'amnezia-xray', 'xray', 'api', 'statsquery',
                               '--server=127.0.0.1:10085', '-pattern', 'user>>>', '-timeout', '5'))
    for record in stats.get('stat', []):
        fields = record.get('name', '').split('>>>')
        if len(fields) == 4 and fields[0] == 'user' and fields[2] == 'traffic' and fields[1] in profiles:
            if fields[3] in ('uplink', 'downlink'):
                profiles[fields[1]]['up' if fields[3] == 'uplink' else 'down'] = int(record.get('value') or 0)
    return list(profiles.values()), missing


def silnet_profiles():
    # The panel already maintains cumulative traffic; the query is read-only and
    # selects no credentials, subscriptions or internal account identifiers.
    sql = ("SELECT COALESCE(json_agg(json_build_object('name', u.username, "
           "'total', t.lifetime_used_traffic_bytes)), '[]'::json) "
           "FROM users u JOIN user_traffic t ON t.id=u.id WHERE u.status='ACTIVE'")
    shell = 'exec psql -X -q -A -t -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"'
    raw = command('docker', 'exec', 'remnawave-db', 'sh', '-c', shell, '_', sql)
    profiles = json.loads(raw)
    for profile in profiles:
        profile['key'] = hashlib.sha256(profile['name'].encode()).hexdigest()[:16]
    return profiles


if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('baloonz_ru', 'baloonz_eu', 'silnet'):
        raise SystemExit(2)
    print(json.dumps(sample_host(sys.argv[1]), ensure_ascii=False, separators=(',', ':')))
