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
XRAY_UUID="${XRAY_UUID:-}"
XRAY_XHTTP_PATH="${XRAY_XHTTP_PATH:-}"
XRAY_REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
XRAY_REALITY_SHORT_ID="${XRAY_REALITY_SHORT_ID:-}"
XRAY_REALITY_SERVER_NAME="${XRAY_REALITY_SERVER_NAME:-www.microsoft.com}"
XRAY_REALITY_DEST="${XRAY_REALITY_DEST:-${XRAY_REALITY_SERVER_NAME}:443}"
APP_DIR="${APP_DIR:-/opt/xray_server}"
NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-8443}"
XRAY_XHTTP_PORT="${XRAY_XHTTP_PORT:-12777}"
XRAY_REALITY_PORT="${XRAY_REALITY_PORT:-12888}"
CLOAK_PORT="${CLOAK_PORT:-18080}"

log() {
  printf '[xray-config] %s\n' "$*"
}

fail() {
  printf '[xray-config] error: %s\n' "$*" >&2
  exit 1
}

require_tty() {
  if [[ ! -t 0 ]]; then
    fail "interactive terminal is required to create .env automatically"
  fi
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

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

validate_host_port() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+:[0-9]+$ ]]
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
    if [[ -z "${value}" ]]; then
      value="${default_value}"
    fi

    if [[ "${required}" == "1" && -z "${value}" ]]; then
      log "value is required"
      continue
    fi

    printf '%s' "${value}"
    return
  done
}

prompt_domain() {
  while true; do
    DOMAIN="$(prompt_text "1/8 Домен для XHTTP через Cloudflare" "${DOMAIN}" 1)"
    if validate_domain "${DOMAIN}"; then
      return
    fi
    log "enter a valid domain like vpn.example.com"
  done
}

prompt_reality_server_name() {
  while true; do
    XRAY_REALITY_SERVER_NAME="$(prompt_text "2/8 SNI для REALITY" "${XRAY_REALITY_SERVER_NAME}" 1)"
    if validate_domain "${XRAY_REALITY_SERVER_NAME}"; then
      return
    fi
    log "enter a valid domain like www.microsoft.com"
  done
}

prompt_reality_dest() {
  while true; do
    XRAY_REALITY_DEST="$(prompt_text "3/8 DEST для REALITY" "${XRAY_REALITY_DEST}" 1)"
    if validate_host_port "${XRAY_REALITY_DEST}"; then
      return
    fi
    log "enter value in host:port format, for example www.microsoft.com:443"
  done
}

prompt_app_dir() {
  APP_DIR="$(prompt_text "4/8 Каталог установки на сервере" "${APP_DIR}" 1)"
}

prompt_port() {
  local label="$1"
  local current_value="$2"
  local result

  while true; do
    result="$(prompt_text "${label}" "${current_value}" 1)"
    if validate_port "${result}"; then
      printf '%s' "${result}"
      return
    fi
    log "port must be between 1 and 65535"
  done
}

prompt_ports() {
  NGINX_HTTP_PORT="$(prompt_port "5/8 Локальный TLS-порт nginx" "${NGINX_HTTP_PORT}")"
  XRAY_XHTTP_PORT="$(prompt_port "6/8 Локальный порт XHTTP inbound" "${XRAY_XHTTP_PORT}")"
  XRAY_REALITY_PORT="$(prompt_port "7/8 Локальный порт REALITY inbound" "${XRAY_REALITY_PORT}")"
  CLOAK_PORT="$(prompt_port "8/8 Локальный порт маскировочного сайта" "${CLOAK_PORT}")"
}

prompt_optional_secret() {
  local label="$1"
  local value="$2"
  prompt_text "${label}" "${value}" 0
}

write_env() {
  cat >"${ENV_FILE}" <<EOF
DOMAIN=${DOMAIN}

# Optional overrides. Leave empty to autogenerate.
XRAY_UUID=${XRAY_UUID}
XRAY_XHTTP_PATH=${XRAY_XHTTP_PATH}
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY}
XRAY_REALITY_PUBLIC_KEY=${XRAY_REALITY_PUBLIC_KEY}
XRAY_REALITY_SHORT_ID=${XRAY_REALITY_SHORT_ID}

# Popular TLS server used by REALITY.
XRAY_REALITY_SERVER_NAME=${XRAY_REALITY_SERVER_NAME}
XRAY_REALITY_DEST=${XRAY_REALITY_DEST}

# Install locations.
APP_DIR=${APP_DIR}
NGINX_HTTP_PORT=${NGINX_HTTP_PORT}
XRAY_XHTTP_PORT=${XRAY_XHTTP_PORT}
XRAY_REALITY_PORT=${XRAY_REALITY_PORT}
CLOAK_PORT=${CLOAK_PORT}
EOF
}

print_next_steps() {
  cat <<EOF

.env written to ${ENV_FILE}

Before installation, make sure:
  1. DNS record ${DOMAIN} points to your VPS.
  2. The ${DOMAIN} record is proxied by Cloudflare for XHTTP.
  3. gRPC is enabled in Cloudflare for ${DOMAIN}.
  4. Port 443/tcp is open on the server.

Next command:
  sudo bash ./install.sh
EOF
}

main() {
  require_tty

  cat <<'EOF'
This wizard prepares the .env file for xray_server.
Press Enter to keep the suggested value shown in brackets.
Leave secret fields empty if you want install.sh to generate them automatically.
EOF

  prompt_domain
  prompt_reality_server_name
  prompt_reality_dest
  prompt_app_dir
  prompt_ports

  XRAY_UUID="$(prompt_optional_secret "Optional UUID override" "${XRAY_UUID}")"
  XRAY_XHTTP_PATH="$(prompt_optional_secret "Optional XHTTP path override" "${XRAY_XHTTP_PATH}")"
  XRAY_REALITY_PRIVATE_KEY="$(prompt_optional_secret "Optional REALITY private key override" "${XRAY_REALITY_PRIVATE_KEY}")"
  XRAY_REALITY_PUBLIC_KEY="$(prompt_optional_secret "Optional REALITY public key override" "${XRAY_REALITY_PUBLIC_KEY}")"
  XRAY_REALITY_SHORT_ID="$(prompt_optional_secret "Optional REALITY shortId override" "${XRAY_REALITY_SHORT_ID}")"

  write_env
  print_next_steps
}

main "$@"
