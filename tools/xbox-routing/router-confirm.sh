#!/bin/sh
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
work=$1
[ "$(cat "$work/status")" = applied ] || exit 1
[ "$(sha256sum /opt/etc/xray/configs/05_routing.json | awk '{print $1}')" = "$(sha256sum "$work/candidate.json" | awk '{print $1}')" ] || exit 1
pidof xray >/dev/null
printf '%s\n' committed > "$work/status"
# The short-lived local rollback copy is removed after the guard observes commit.
nohup sh -c 'sleep 250; rm -rf "$1"' sh "$work" </dev/null >/dev/null 2>&1 &
echo committed
