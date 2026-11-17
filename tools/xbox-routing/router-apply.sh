#!/bin/sh
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
work=$1
config=/opt/etc/xray/configs/05_routing.json
[ "$(cat "$work/status")" = prepared ] || exit 1
[ "$(sha256sum "$config" | awk '{print $1}')" = "$(cat "$work/expected.sha256")" ] || { echo drift; exit 1; }
candidate_hash=$(sha256sum "$work/candidate.json" | awk '{print $1}')
cat > "$work/guard.sh" <<'EOF'
#!/bin/sh
set -u
work=$1
candidate_hash=$2
config=/opt/etc/xray/configs/05_routing.json
sleep 240
case "$(cat "$work/status" 2>/dev/null)" in committed|rolled-back) exit 0;; esac
current=$(sha256sum "$config" | awk '{print $1}')
if [ "$current" != "$candidate_hash" ]; then printf '%s\n' rollback-drift > "$work/status"; exit 1; fi
cp -p "$work/original.json" /opt/etc/xray/configs/.05-routing-rollback && mv /opt/etc/xray/configs/.05-routing-rollback "$config" || exit 1
if sh /opt/etc/init.d/S24xray restart on >/dev/null 2>&1; then printf '%s\n' rolled-back > "$work/status"; else printf '%s\n' rollback-failed > "$work/status"; fi
EOF
chmod 700 "$work/guard.sh"
nohup sh "$work/guard.sh" "$work" "$candidate_hash" </dev/null >/dev/null 2>&1 &
guard=$!
sleep 1
kill -0 "$guard" 2>/dev/null || { echo guard_failed; exit 1; }
cp -p "$work/candidate.json" /opt/etc/xray/configs/.05-routing-new
mv /opt/etc/xray/configs/.05-routing-new "$config"
printf '%s\n' applied > "$work/status"
if ! sh /opt/etc/init.d/S24xray restart on >/dev/null 2>&1 || ! pidof xray >/dev/null; then
    cp -p "$work/original.json" /opt/etc/xray/configs/.05-routing-rollback
    mv /opt/etc/xray/configs/.05-routing-rollback "$config"
    sh /opt/etc/init.d/S24xray restart on >/dev/null 2>&1 || { echo rollback_failed; exit 1; }
    printf '%s\n' rolled-back > "$work/status"
    echo apply_failed_rolled_back
    exit 1
fi
echo applied_guard_armed
