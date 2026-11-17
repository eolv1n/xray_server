#!/usr/bin/env python3
"""Check dashboard queries without printing sensitive metric labels."""
import json
import subprocess
import sys
import urllib.parse

data = json.load(open(sys.argv[1], encoding='utf-8'))
errors, empty, count = [], [], 0
for panel in data['panels']:
    for query in panel.get('targets', []):
        count += 1
        encoded = urllib.parse.urlencode({'query': query['expr']})
        raw = subprocess.check_output(['docker', 'exec', 'infrastek-server-prometheus-1',
                                       'wget', '-qO-', 'http://127.0.0.1:9090/api/v1/query?' + encoded])
        response = json.loads(raw)
        if response.get('status') != 'success':
            errors.append(panel['title'])
        elif not response['data']['result']:
            empty.append(panel['title'])
print('queries:', count, 'errors:', errors, 'currently empty:', empty)
if errors:
    raise SystemExit(1)
