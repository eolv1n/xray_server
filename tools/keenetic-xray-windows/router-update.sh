#!/bin/sh
# Update the Entware/XKeen Xray binary on a Keenetic. Do not print VPN secrets.
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077

version=26.10.31
root=/opt/etc/xray
binary=/opt/sbin/xray
init=/opt/etc/init.d/S24xray
configs=$root/configs
state=/opt/var/backups/xray-update
lock=/opt/var/run/xray-windows-update.lock
work=
test_pid=
applied=0
tx=
locked=0

say() { printf '%s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }
stop_test() {
    if [ -n "$test_pid" ]; then
        kill "$test_pid" 2>/dev/null || :
        wait "$test_pid" 2>/dev/null || :
        test_pid=
    fi
}
rollback() {
    [ -n "$tx" ] && [ -f "$tx/xray.previous" ] || return 1
    cp -p "$tx/xray.previous" /opt/sbin/.xray-rollback-$$ || return 1
    mv -f /opt/sbin/.xray-rollback-$$ "$binary" || return 1
    sh "$init" restart on >/dev/null 2>&1 || return 1
    printf '%s\n' rolled-back >"$tx/status"
    applied=0
    say 'Previous Xray restored.'
}
cleanup() {
    stop_test
    if [ "$applied" = 1 ]; then
        rollback || say 'ERROR: Automatic rollback failed; use the router console.' >&2
    fi
    [ -z "$work" ] || rm -rf "$work"
    if [ "$locked" = 1 ]; then rmdir "$lock" 2>/dev/null || :; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

[ "$(id -u)" = 0 ] || fail 'Connect as root to the Entware SSH server.'
[ -d /opt/etc/ndm ] || [ -e /etc/ndm ] || [ -f /etc/ndm-release ] || {
    uname -a | grep -qi keenetic || fail 'This does not look like a Keenetic router.'
}
[ -x "$binary" ] && [ ! -L "$binary" ] && [ -f "$init" ] && [ -d "$configs" ] || fail 'XKeen layout was not found; no changes made.'
for tool in curl unzip jq sha256sum nohup pidof awk base64; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool is missing: $tool"
done
case "$(uname -m)" in
    aarch64|arm64) archive=Xray-linux-arm64-v8a.zip; digest=1811c8f1da0c3b6dc707ebaf1c8390e987ba39859a8f0a7aadd8526157f2ec8d ;;
    armv7l|armv7*) archive=Xray-linux-arm32-v7a.zip; digest=2387f55239ee7799fd67d5382e79f589c1da07a97d993e86b058f2290b8e456b ;;
    *) fail 'Unsupported CPU architecture; no changes made.' ;;
esac

current=$("$binary" version 2>/dev/null | awk 'NR==1 {print $2}')
case "$current" in ''|*[!0-9.]*) fail 'Could not identify the installed Xray version.';; esac
say "Installed Xray: $current; target: $version"
if awk -v a="$current" -v b="$version" 'BEGIN {split(a,x,"."); split(b,y,"."); for(i=1;i<=3;i++){if((x[i]+0)>(y[i]+0)) exit 0; if((x[i]+0)<(y[i]+0)) exit 1} exit 0}'; then
    say 'Xray is already at this version or newer; no changes made.'
    exit 0
fi

mkdir -p /opt/var/run /opt/var/tmp "$state"
chmod 700 "$state"
mkdir "$lock" 2>/dev/null || fail 'Another update is running or its lock needs inspection.'
locked=1
work=$(mktemp -d /opt/var/tmp/xray-windows-update.XXXXXX)
chmod 700 "$work"
outbound=$configs/04_outbounds.json
[ -f "$outbound" ] || fail 'Expected XKeen outbound configuration is missing.'
jq -e '[.outbounds[] | select(.protocol == "vless" and .streamSettings.security == "reality")] | length == 1' "$outbound" >/dev/null 2>&1 || fail 'Expected exactly one VLESS REALITY outbound; no changes made.'

say 'Downloading the official Xray release and checking SHA-256...'
curl -fsSL --retry 2 --connect-timeout 15 --max-time 150 -o "$work/xray.zip" "https://github.com/XTLS/Xray-core/releases/download/v$version/$archive" || fail 'Download failed. Check router internet access.'
printf '%s  %s\n' "$digest" "$work/xray.zip" | sha256sum -c - >/dev/null || fail 'Archive checksum mismatch.'
unzip -q "$work/xray.zip" xray -d "$work" || fail 'Could not extract the official release.'
chmod 755 "$work/xray"
new_hash=$(sha256sum "$work/xray" | awk '{print $1}')
XRAY_LOCATION_ASSET="$root/dat" XRAY_LOCATION_CONFDIR="$configs" "$work/xray" run -test -confdir "$configs" >"$work/config-check.log" 2>&1 || fail 'New Xray rejected the current configuration; no changes made.'

# The temporary test profile stays on the router with mode 0600 and is deleted.
jq -e '{log:{loglevel:"warning"},inbounds:[{listen:"127.0.0.1",port:19191,protocol:"socks",settings:{udp:false}}],outbounds:[.outbounds[] | select(.protocol == "vless" and .streamSettings.security == "reality")]}' "$outbound" >"$work/test.json"

test_vpn() {
    XRAY_LOCATION_ASSET="$root/dat" "$binary" run -c "$work/test.json" >"$work/test.log" 2>&1 &
    test_pid=$!
    sleep 2
    if ! kill -0 "$test_pid" 2>/dev/null; then stop_test; return 1; fi
    if curl --noproxy '' --socks5-hostname 127.0.0.1:19191 -fsS --connect-timeout 8 --max-time 20 -o /dev/null https://www.wikipedia.org/ 2>/dev/null || \
       curl --noproxy '' --socks5-hostname 127.0.0.1:19191 -fsS --connect-timeout 8 --max-time 20 -o /dev/null https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null; then
        stop_test
        return 0
    fi
    stop_test
    return 1
}

# Test the new executable without replacing the running program.
old_binary=$binary
binary=$work/xray
test_vpn || fail 'The new Xray could not connect using the saved VPN profile; no changes made.'
binary=$old_binary

tx=$state/$(date -u +%Y%m%dT%H%M%SZ)-$$
mkdir -m 700 "$tx"
cp -p "$binary" "$tx/xray.previous"
printf '%s\n' pending >"$tx/status"
cat >"$tx/watchdog.sh" <<'GUARD'
#!/bin/sh
set -u
tx=$1
sleep 180
status=$(cat "$tx/status" 2>/dev/null || echo missing)
case "$status" in committed|rolled-back) exit 0;; esac
cp -p "$tx/xray.previous" /opt/sbin/.xray-auto-rollback-$$ || exit 1
mv -f /opt/sbin/.xray-auto-rollback-$$ /opt/sbin/xray || exit 1
if sh /opt/etc/init.d/S24xray restart on >/dev/null 2>&1; then
    printf '%s\n' rolled-back >"$tx/status"
else
    printf '%s\n' rollback-failed >"$tx/status"
fi
GUARD
chmod 700 "$tx/watchdog.sh"
nohup sh "$tx/watchdog.sh" "$tx" </dev/null >/dev/null 2>&1 &
guard=$!
sleep 1
kill -0 "$guard" 2>/dev/null || fail 'Could not start automatic rollback.'
cp -p "$work/xray" /opt/sbin/.xray-new-$$
mv -f /opt/sbin/.xray-new-$$ "$binary"
applied=1
say 'Restarting Xray; automatic rollback is armed...'
sh "$init" restart on >/dev/null 2>&1 || fail 'Xray restart failed.'
sleep 3
running=0
for pid in $(pidof xray 2>/dev/null || :); do
    hash=$(sha256sum "/proc/$pid/exe" 2>/dev/null | awk '{print $1}') || :
    [ "${hash:-}" = "$new_hash" ] && running=1
done
[ "$running" = 1 ] || fail 'The updated Xray process is not running.'
test_vpn || fail 'VPN connection test failed after restart.'
printf '%s\n' committed >"$tx/status"
applied=0
say "SUCCESS: Xray $version is installed and the VPN test passed."
say "The previous binary is retained on the router: $tx/xray.previous"
