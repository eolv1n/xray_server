#!/usr/bin/env python3
"""Check provisioned dashboard using container credentials without logging them."""
import base64
import json
import subprocess
import sys
import urllib.request

container = json.loads(subprocess.check_output(['docker', 'inspect', 'infrastek-server-grafana-1']))[0]
env = dict(item.split('=', 1) for item in container['Config']['Env'] if '=' in item)
token = base64.b64encode((env['GF_SECURITY_ADMIN_USER'] + ':' + env['GF_SECURITY_ADMIN_PASSWORD']).encode()).decode()
uid = sys.argv[1] if len(sys.argv) > 1 else 'vpn-observability'
path = '/api/search?type=dash-db' if uid == '--list' else '/api/dashboards/uid/' + uid
request = urllib.request.Request('http://127.0.0.1:3000' + path,
                                 headers={'Authorization': 'Basic ' + token})
with urllib.request.urlopen(request, timeout=5) as response:
    data = json.load(response)
if uid == '--list':
    print('VPN dashboards:', [(item['uid'], item['title']) for item in data if item['uid'].startswith('vpn-observability')])
else:
    dashboard = data['dashboard']
    print('dashboard:', dashboard['title'], 'panels:', len(dashboard['panels']))
