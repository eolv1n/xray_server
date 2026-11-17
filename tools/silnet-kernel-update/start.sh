#!/usr/bin/env bash
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
payload=$script_dir/remote-update.sh
[ -f "$payload" ] || { echo 'Update script not found.'; exit 1; }
encoded=$(base64 -w0 "$payload")
echo 'Silnet: sudo password will be requested by SSH; it is not stored.'
echo 'The script installs the kernel and checks services. It does not reboot the server.'
ssh -F "$HOME/.ssh/config" -o IPQoS=none -o ConnectTimeout=10 -tt silnetbridge "sudo bash -c 'printf %s $encoded | base64 -d | bash'"
