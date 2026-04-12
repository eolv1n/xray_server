#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[stack-install] %s\n' "$*"
}

fail() {
  printf '[stack-install] error: %s\n' "$*" >&2
  exit 1
}

require_tty() {
  [[ -t 0 ]] || fail "interactive terminal is required"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "run this script as root"
}

prompt_choice() {
  local value

  read -r -p "Select option [0-3]: " value
  printf '%s' "${value}"
}

show_menu() {
  cat <<'EOF'
Xray stack installer

1. Panel + node on one server
2. Node only for an existing panel
3. Clean 3x-ui + Angie (mask + panel proxy)
4. Server bootstrap only
0. Exit
EOF
}

show_hints() {
  cat <<'EOF'

Scenario hints:

1. Panel + node on one server
   Required:
   - REMNAWAVE_PANEL_DOMAIN
   - REMNAWAVE_SUB_DOMAIN
   - REMNAWAVE_NODE_DOMAIN
   - LETSENCRYPT_EMAIL

2. Node only for an existing panel
   Required:
   - REMNAWAVE_NODE_DOMAIN
   - REMNAWAVE_PANEL_IP
   - LETSENCRYPT_EMAIL
   - REMNAWAVE_NODE_SECRET_KEY_FILE or REMNAWAVE_NODE_SECRET_KEY

3. Clean 3x-ui + Angie
   Required:
   - XUI_PANEL_DOMAIN
   - XUI_MASK_DOMAIN
   - LETSENCRYPT_EMAIL

4. Server bootstrap only
   Use this first on a clean VPS before any Remnawave install.
EOF
}

run_panel_node() {
  exec bash "${REPO_DIR}/install-remnawave-panel-node.sh"
}

run_node_only() {
  exec bash "${REPO_DIR}/install-remnawave-node.sh"
}

run_3xui_angie() {
  exec bash "${REPO_DIR}/install-3xui-angie.sh"
}

run_bootstrap() {
  exec bash "${REPO_DIR}/bootstrap-server.sh"
}

main() {
  require_tty
  require_root

  while true; do
    show_menu
    show_hints
    printf '\n'

    case "$(prompt_choice)" in
      1)
        run_panel_node
        ;;
      2)
        run_node_only
        ;;
      3)
        run_3xui_angie
        ;;
      4)
        run_bootstrap
        ;;
      0)
        log "exit"
        exit 0
        ;;
      *)
        printf '\n'
        log "invalid choice"
        printf '\n'
        ;;
    esac
  done
}

main "$@"
