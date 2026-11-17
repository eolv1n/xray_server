#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
PATH=/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" = 0 ] || { echo 'ERROR: root is required'; exit 1; }
[ "$(hostname)" = Edge-01 ] || { echo 'ERROR: unexpected host'; exit 1; }
. /etc/os-release
[ "$ID" = ubuntu ] && [ "$VERSION_ID" = 26.04 ] || { echo 'ERROR: unexpected OS'; exit 1; }
services=(remnanode remnawave-subscription-page remnawave remnawave-redis remnawave-nginx remnawave-db)
check_services() {
  systemctl is-active --quiet docker && systemctl is-active --quiet ssh.socket || return 1
  systemctl is-enabled --quiet docker && systemctl is-enabled --quiet ssh.socket || return 1
  for c in "${services[@]}"; do
    [ "$(docker inspect -f '{{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' "$c")" = 'true always' ] || return 1
    h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c")
    [ "$h" = none ] || [ "$h" = healthy ] || return 1
  done
}
check_services || { echo 'ERROR: service or boot preflight failed'; exit 1; }
[ -z "$(dpkg --audit)" ] || { echo 'ERROR: dpkg audit failed'; exit 1; }
echo 'Preflight passed. Updating package lists...'
apt-get update -o Acquire::Retries=2 -o Acquire::http::Timeout=20
candidate=$(apt-cache policy linux-image-generic | awk '/Candidate:/ {print $2}')
dpkg --compare-versions "$candidate" ge 7.0.0-43.43 || { echo 'ERROR: fixed kernel is not available'; exit 1; }
echo "Installing kernel package $candidate..."
apt-get -y -o Dpkg::Options::=--force-confold install linux-generic
[ -z "$(dpkg --audit)" ] || { echo 'ERROR: package installation is incomplete; reboot cancelled'; exit 1; }
installed=$(dpkg-query -W -f='${Version}' linux-image-generic)
dpkg --compare-versions "$installed" ge 7.0.0-43.43 || { echo 'ERROR: fixed kernel not installed'; exit 1; }
image=$(readlink -f /boot/vmlinuz)
initrd=$(readlink -f /boot/initrd.img)
[ -s "$image" ] && [ -s "$initrd" ] || { echo 'ERROR: boot files missing'; exit 1; }
imageversion=${image##*vmlinuz-}
case "$imageversion" in 7.0.0-*) ;; *) echo 'ERROR: unexpected default kernel'; exit 1;; esac
imagepackage=$(dpkg-query -W -f='${Version}' "linux-image-$imageversion")
dpkg --compare-versions "$imagepackage" ge 7.0.0-43.43 || { echo 'ERROR: default image is not fixed'; exit 1; }
[ "$imageversion" != "$(uname -r)" ] || { echo 'ERROR: default kernel did not change'; exit 1; }
[ "${initrd##*initrd.img-}" = "$imageversion" ] || { echo 'ERROR: kernel and initrd do not match'; exit 1; }
check_services || { echo 'ERROR: service check failed; reboot cancelled'; exit 1; }
echo "Ready: installed $installed, boot files for $imageversion verified; all six services are running."
echo 'KERNEL_READY; no reboot scheduled.'
