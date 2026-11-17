#!/bin/sh
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
work=$1
expected=$2
config=/opt/etc/xray/configs
[ -d "$work" ] && [ -f "$work/candidate.jq" ] || exit 2
[ "$(sha256sum "$config/05_routing.json" | awk '{print $1}')" = "$expected" ] || { echo drift; exit 1; }
jq -e 'any(.outbounds[]; .tag == "vless-reality-test" and .protocol == "vless") and any(.outbounds[]; .tag == "direct" and .protocol == "freedom")' "$config/04_outbounds.json" >/dev/null
jq -e '[.inbounds[].tag] | index("redirect") != null and index("tproxy") != null' "$config/03_inbounds.json" >/dev/null
mkdir -m 700 "$work/check"
cp -p "$config"/*.json "$work/check/"
cp -p "$config/05_routing.json" "$work/original.json"
jq --argjson sources '["192.168.1.85/32","192.168.1.150/32"]' -f "$work/candidate.jq" "$work/original.json" > "$work/check/05_routing.json.new"
mv "$work/check/05_routing.json.new" "$work/check/05_routing.json"
XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR="$work/check" /opt/sbin/xray run -test -confdir "$work/check" > "$work/config-test.log" 2>&1 || { echo xray_config_invalid; exit 1; }
cp -p "$work/check/05_routing.json" "$work/candidate.json"
rm -rf "$work/check"
printf '%s\n' "$expected" > "$work/expected.sha256"
printf '%s\n' prepared > "$work/status"
echo candidate_config=valid
jq -c '[.routing.rules[] | select((.source // []) == ["192.168.1.85/32","192.168.1.150/32"]) | {source,outboundTag,domains:(.domain|length)}]' "$work/candidate.json"
