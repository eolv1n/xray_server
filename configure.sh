#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
elif [[ -f "${EXAMPLE_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${EXAMPLE_ENV_FILE}"
fi

DOMAIN="${DOMAIN:-}"
APP_DIR="${APP_DIR:-/opt/xray-vps-setup}"
XRAY_UUID="${XRAY_UUID:-}"
XRAY_PRIVATE_KEY="${XRAY_PRIVATE_KEY:-}"
XRAY_PUBLIC_KEY="${XRAY_PUBLIC_KEY:-}"
XRAY_SHORT_ID="${XRAY_SHORT_ID:-}"
MARZBAN_USER="${MARZBAN_USER:-}"
MARZBAN_PASS="${MARZBAN_PASS:-}"
MARZBAN_DASHBOARD_PATH="${MARZBAN_DASHBOARD_PATH:-}"
MARZBAN_SUBSCRIPTION_PATH="${MARZBAN_SUBSCRIPTION_PATH:-}"
PANEL_ALLOWLIST="${PANEL_ALLOWLIST:-}"
XRAY_CORE_VERSION="${XRAY_CORE_VERSION:-26.2.6}"
XRAY_IMAGE_TAG="${XRAY_IMAGE_TAG:-26.3.27}"
MARZBAN_IMAGE="${MARZBAN_IMAGE:-gozargah/marzban:latest}"

log() {
  printf '[xray-config] %s\n' "$*"
}

fail() {
  printf '[xray-config] error: %s\n' "$*" >&2
  exit 1
}

require_tty() {
  [[ -t 0 ]] || fail "interactive terminal is required"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

validate_domain() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ && "$1" == *.* ]]
}

prompt_text() {
  local label="$1"
  local default_value="$2"
  local required="${3:-0}"
  local value

  while true; do
    if [[ -n "${default_value}" ]]; then
      read -r -p "${label} [${default_value}]: " value
    else
      read -r -p "${label}: " value
    fi

    value="$(trim "${value}")"
    [[ -n "${value}" ]] || value="${default_value}"

    if [[ "${required}" == "1" && -z "${value}" ]]; then
      log "value is required"
      continue
    fi

    printf '%s' "${value}"
    return
  done
}

prompt_domain_value() {
  local label="$1"
  local current="$2"
  local value

  while true; do
    value="$(prompt_text "${label}" "${current}" 1)"
    if validate_domain "${value}"; then
      printf '%s' "${value}"
      return
    fi
    log "enter a valid domain like edge.example.net"
  done
}

write_env() {
  cat >"${ENV_FILE}" <<EOF
DOMAIN=${DOMAIN}
APP_DIR=${APP_DIR}

# Optional overrides. Leave empty to autogenerate.
XRAY_UUID=${XRAY_UUID}
XRAY_PRIVATE_KEY=${XRAY_PRIVATE_KEY}
XRAY_PUBLIC_KEY=${XRAY_PUBLIC_KEY}
XRAY_SHORT_ID=${XRAY_SHORT_ID}
MARZBAN_USER=${MARZBAN_USER}
MARZBAN_PASS=${MARZBAN_PASS}
MARZBAN_DASHBOARD_PATH=${MARZBAN_DASHBOARD_PATH}
MARZBAN_SUBSCRIPTION_PATH=${MARZBAN_SUBSCRIPTION_PATH}
PANEL_ALLOWLIST=${PANEL_ALLOWLIST}

# Runtime versions.
XRAY_CORE_VERSION=${XRAY_CORE_VERSION}
XRAY_IMAGE_TAG=${XRAY_IMAGE_TAG}
MARZBAN_IMAGE=${MARZBAN_IMAGE}
EOF
}

main() {
  require_tty

  cat <<'EOF'
This wizard prepares the .env file for the Xray + Marzban stack.
Press Enter to keep the suggested value shown in brackets.
Leave secret fields empty to let install.sh generate them automatically.
EOF

  DOMAIN="$(prompt_domain_value "1/3 Domain for Xray and Marzban panel" "${DOMAIN}")"
  APP_DIR="$(prompt_text "2/3 Install directory" "${APP_DIR}" 1)"
  MARZBAN_IMAGE="$(prompt_text "3/3 Marzban image" "${MARZBAN_IMAGE}" 1)"

  XRAY_UUID="$(prompt_text "Optional UUID override" "${XRAY_UUID}" 0)"
  XRAY_PRIVATE_KEY="$(prompt_text "Optional REALITY private key override" "${XRAY_PRIVATE_KEY}" 0)"
  XRAY_PUBLIC_KEY="$(prompt_text "Optional REALITY public key override" "${XRAY_PUBLIC_KEY}" 0)"
  XRAY_SHORT_ID="$(prompt_text "Optional REALITY shortId override" "${XRAY_SHORT_ID}" 0)"
  MARZBAN_USER="$(prompt_text "Optional Marzban admin user override" "${MARZBAN_USER}" 0)"
  MARZBAN_PASS="$(prompt_text "Optional Marzban admin password override" "${MARZBAN_PASS}" 0)"
  MARZBAN_DASHBOARD_PATH="$(prompt_text "Optional hidden dashboard path override" "${MARZBAN_DASHBOARD_PATH}" 0)"
  MARZBAN_SUBSCRIPTION_PATH="$(prompt_text "Optional subscription path override" "${MARZBAN_SUBSCRIPTION_PATH}" 0)"
  PANEL_ALLOWLIST="$(prompt_text "Optional panel allowlist (comma-separated CIDRs)" "${PANEL_ALLOWLIST}" 0)"

  write_env

  cat <<EOF

.env written to ${ENV_FILE}

Before installation, make sure:
  1. ${DOMAIN} points to your VPS.
  2. Ports 80/tcp and 443/tcp are open on the server.

Next command:
  sudo bash ./install.sh
EOF
}

main "$@"
