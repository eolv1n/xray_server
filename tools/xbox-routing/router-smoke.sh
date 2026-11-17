#!/bin/sh
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
work=$1
pid=
cleanup() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi
    rm -f "$work/smoke.json" "$work/smoke.log"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
jq -e '{log:{loglevel:"warning"},inbounds:[{listen:"127.0.0.1",port:19193,protocol:"socks",settings:{udp:false}}],outbounds:[.outbounds[]|select(.tag=="vless-reality-test")]}' /opt/etc/xray/configs/04_outbounds.json > "$work/smoke.json"
XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -c "$work/smoke.json" > "$work/smoke.log" 2>&1 &
pid=$!
sleep 2
kill -0 "$pid" 2>/dev/null || { echo smoke_xray_start_failed; exit 1; }
code=$(curl --noproxy '' --socks5-hostname 127.0.0.1:19193 -sS -o /dev/null --connect-timeout 8 --max-time 20 -w '%{http_code}' https://www.wikipedia.org/ 2>/dev/null) || { echo vpn_smoke_failed; exit 1; }
[ "$code" = 200 ] || { echo vpn_smoke_failed; exit 1; }
echo vpn_smoke=ok
