#!/usr/bin/env python3
"""Generate the VPN dashboard using Grafana's native visualizations."""
import json
from pathlib import Path
import sys

DS = {'type': 'prometheus', 'uid': 'PBFA97CFB590B2093'}
NODES = [('baloonz_ru', 'Baloonz RU'), ('baloonz_eu', 'Baloonz EU'), ('silnet', 'Silnet')]
panels = []


def panel(title, kind, x, y, w, h, description=''):
    p = {'id': len(panels) + 1, 'title': title, 'type': kind, 'datasource': DS,
         'description': description, 'gridPos': {'x': x, 'y': y, 'w': w, 'h': h},
         'fieldConfig': {'defaults': {'unit': 'short', 'noValue': 'NO DATA'}, 'overrides': []},
         'targets': []}
    panels.append(p)
    return p


def add_query(p, expr, label='', instant=True):
    p['targets'].append({'refId': chr(65 + len(p['targets'])), 'expr': expr,
                         'legendFormat': label, 'instant': instant})


def compact_stat(title, x, y, w, h, queries, unit='short', status=False, description=''):
    p = panel(title, 'stat', x, y, w, h, description)
    default = p['fieldConfig']['defaults']
    default.update({'unit': unit, 'color': {'mode': 'fixed', 'fixedColor': 'light-blue'}})
    p['options'] = {'reduceOptions': {'calcs': ['lastNotNull'], 'values': False},
                    'orientation': 'auto', 'textMode': 'value_and_name', 'colorMode': 'value',
                    'graphMode': 'none', 'text': {'titleSize': 12, 'valueSize': 16}}
    if status:
        default.update({'color': {'mode': 'thresholds'},
                        'thresholds': {'mode': 'absolute', 'steps': [
                            {'color': 'gray', 'value': None}, {'color': 'red', 'value': 0}, {'color': 'green', 'value': 1}]},
                        'mappings': [{'type': 'value', 'options': {
                            '-1': {'text': 'NO DATA', 'color': 'gray'},
                            '0': {'text': 'DOWN', 'color': 'red'},
                            '1': {'text': 'UP', 'color': 'green'}}}]})
    for expr, label in queries:
        add_query(p, expr, label)
    return p


def selector(node, service=None):
    return '{node="' + node + '"' + (',service="' + service + '"' if service else '') + '}'


def cpu(node):
    s = selector(node)
    return '100 * (1 - rate(vpn_node_cpu_idle_seconds_total' + s + '[5m]) / rate(vpn_node_cpu_seconds_total' + s + '[5m]))'


def gauge(title, x, expr):
    p = panel(title, 'bargauge', x, 7, 8, 7,
              'Percentage used. Memory uses MemAvailable; disk includes filesystem reserved space.')
    p['fieldConfig']['defaults'].update({'unit': 'percent', 'min': 0, 'max': 100,
        'color': {'mode': 'thresholds'}, 'thresholds': {'mode': 'absolute', 'steps': [
            {'color': 'blue', 'value': None}, {'color': 'yellow', 'value': 75}, {'color': 'red', 'value': 90}]}})
    p['options'] = {'orientation': 'horizontal', 'displayMode': 'basic', 'showUnfilled': True,
                    'namePlacement': 'left', 'barSize': 'manual', 'minVizHeight': 22, 'maxVizHeight': 30,
                    'reduceOptions': {'calcs': ['lastNotNull'], 'values': False},
                    'text': {'titleSize': 12, 'valueSize': 14}}
    for node, label in NODES:
        add_query(p, expr(node), label)


def graph(title, x, y, w, h, unit, queries, description='', max_value=None):
    p = panel(title, 'timeseries', x, y, w, h, description)
    p['fieldConfig']['defaults'].update({'unit': unit, 'color': {'mode': 'palette-classic'},
        'custom': {'drawStyle': 'line', 'lineWidth': 2, 'fillOpacity': 10, 'showPoints': 'never', 'spanNulls': False}})
    if max_value is not None:
        p['fieldConfig']['defaults'].update({'min': 0, 'max': max_value})
    p['options'] = {'legend': {'displayMode': 'list', 'placement': 'bottom', 'calcs': []},
                    'tooltip': {'mode': 'multi', 'sort': 'desc'}}
    for expr, label in queries:
        add_query(p, expr, label, False)


availability = []
for node, label in NODES:
    s = selector(node)
    availability.append(('(vpn_observer_success' + s + ' * on(node,project) '
                         '(time() - vpn_observer_attempt_timestamp_seconds' + s + ' < bool 150)) or vector(-1)', label))
compact_stat('Nodes', 0, 0, 6, 7, availability, status=True,
             description='SSH collection status, not an end-to-end VPN check.')
docker_services = [('baloonz_ru', 'amnezia-xray', 'RU · Xray'), ('baloonz_ru', 'wg-easy', 'RU · WG Easy'),
                   ('silnet', 'remnanode', 'Silnet · Node'), ('silnet', 'remnawave', 'Silnet · Panel'),
                   ('silnet', 'remnawave-nginx', 'Silnet · Nginx'), ('silnet', 'remnawave-subscription-page', 'Silnet · Subscriptions'),
                   ('silnet', 'remnawave-db', 'Silnet · PostgreSQL'), ('silnet', 'remnawave-redis', 'Silnet · Redis')]
def service_state(node, service):
    s = selector(node)
    return ('(vpn_service_healthy' + selector(node, service) + ' and on(node,project) '
            '((vpn_observer_success' + s + ' == 1) and on(node,project) '
            '(time() - vpn_observer_attempt_timestamp_seconds' + s + ' < 150))) or vector(-1)')


compact_stat('Docker', 6, 0, 12, 7,
             [(service_state(node, service), label) for node, service, label in docker_services],
             status=True, description='Container running state and health check when available.')
wg_services = [('wg-quick@bzovhwg0', 'WireGuard'), ('baloonz-ovh-wg-exit', 'EU exit')]
compact_stat('WireGuard · EU', 18, 0, 6, 7,
             [(service_state('baloonz_eu', name), label) for name, label in wg_services],
             status=True, description='Systemd service state; does not prove end-to-end connectivity.')

gauge('CPU · %', 0, cpu)
gauge('Memory · % used', 8, lambda n: '100 * (1 - vpn_node_memory_available_bytes' + selector(n) + ' / vpn_node_memory_bytes' + selector(n) + ')')
gauge('Disk · % used', 16, lambda n: '100 * (1 - vpn_node_disk_available_bytes' + selector(n) + ' / vpn_node_disk_bytes' + selector(n) + ')')

def sizes(total, free, used):
    return [((total + selector(n) + ' - ' if used else '') + free + selector(n), label) for n, label in NODES]

compact_stat('Memory · used', 0, 14, 6, 4, sizes('vpn_node_memory_bytes', 'vpn_node_memory_available_bytes', True), 'bytes')
compact_stat('Memory · available', 6, 14, 6, 4, sizes('vpn_node_memory_bytes', 'vpn_node_memory_available_bytes', False), 'bytes',
             description='MemAvailable includes reclaimable cache.')
compact_stat('Disk · used', 12, 14, 6, 4, sizes('vpn_node_disk_bytes', 'vpn_node_disk_available_bytes', True), 'bytes',
             description='Includes filesystem reserved space.')
compact_stat('Disk · available', 18, 14, 6, 4, sizes('vpn_node_disk_bytes', 'vpn_node_disk_available_bytes', False), 'bytes')

graph('CPU history', 0, 18, 24, 7, 'percent', [(cpu(node), label) for node, label in NODES],
      'Five-minute average.', 100)
for i, (node, label) in enumerate(NODES):
    s = selector(node)
    graph(label + ' · network', i * 8, 25, 8, 7, 'bps', [
        ('8 * rate(vpn_node_network_rx_bytes_total' + s + '[5m])', 'RX'),
        ('8 * rate(vpn_node_network_tx_bytes_total' + s + '[5m])', 'TX')],
        'Five-minute average on the default interface.')
compact_stat('Profiles active · 5m', 0, 32, 8, 4,
    [('sum by (project) (sum by (project,profile_id) (increase(vpn_profile_traffic_bytes_total[5m])) > bool 0)', '{{project}}')],
    description='Profiles with traffic; not a count of people or devices.')
compact_stat('Profile counters', 8, 32, 8, 4, [('vpn_profile_observation_success', '{{node}}')], status=True)
compact_stat('Profiles without Xray ID', 16, 32, 8, 4, [('vpn_profiles_missing_identifier', 'Baloonz')],
    description='These profiles are excluded from per-profile statistics.')
p = panel('Profile traffic · 24h', 'table', 0, 36, 24, 8,
          'History begins when monitoring was enabled; counter resets may cause undercounting.')
p['fieldConfig']['defaults']['unit'] = 'bytes'
add_query(p, 'sum by (project,profile,profile_id) (increase(vpn_profile_traffic_bytes_total[24h]))', '{{project}} / {{profile}}')
graph('WireGuard · handshake age', 0, 44, 12, 7, 's',
      [('time() - (vpn_wireguard_handshake_timestamp_seconds > 0)', '{{node}}')],
      'Missing handshake data does not imply that the tunnel is healthy.')
graph('Interface errors and drops', 12, 44, 12, 7, 'pps',
      [('rate(vpn_node_network_rx_errors_total[5m]) + rate(vpn_node_network_tx_errors_total[5m]) + '
        'rate(vpn_node_network_rx_dropped_total[5m]) + rate(vpn_node_network_tx_dropped_total[5m])', '{{node}}')],
      'Interface counters; not an end-to-end packet loss measurement.')

# Grafana processes panel array order during grid placement: always emit row order.
panels.sort(key=lambda p: (p['gridPos']['y'], p['gridPos']['x']))
dashboard = {'id': None, 'uid': 'vpn-observability', 'title': 'VPN: Baloonz and Silnet',
             'description': 'VPN operations. Metric history is stored on cp-01.', 'schemaVersion': 39,
             'version': 3, 'editable': True, 'timezone': 'browser', 'time': {'from': 'now-6h', 'to': 'now'},
             'refresh': '1m', 'tags': ['vpn', 'baloonz', 'silnet'], 'panels': panels}
target_path = (Path(sys.argv[1]) if len(sys.argv) > 1 else
               Path(__file__).resolve().parents[2] / 'shared/grafana/dashboards/overview/vpn-overview.json')
target_path.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2) + '\n')
