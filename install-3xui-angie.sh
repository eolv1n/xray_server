#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"
XUI_INSTALL_URL="${XUI_INSTALL_URL:-https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh}"

log() {
  printf '[3xui-angie] %s\n' "$*"
}

fail() {
  printf '[3xui-angie] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "run this script as root"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
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
  local default_value="${2:-}"
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

prompt_domain() {
  local label="$1"
  local current="$2"
  local value

  while true; do
    value="$(prompt_text "${label}" "${current}" 1)"
    if validate_domain "${value}"; then
      printf '%s' "${value}"
      return
    fi
    log "enter a valid domain"
  done
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  elif [[ -f "${EXAMPLE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${EXAMPLE_ENV_FILE}"
  fi

  XUI_PANEL_DOMAIN="${XUI_PANEL_DOMAIN:-}"
  XUI_MASK_DOMAIN="${XUI_MASK_DOMAIN:-}"
  XUI_PANEL_PORT="${XUI_PANEL_PORT:-2053}"
  LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
}

ensure_config() {
  if [[ -n "${XUI_PANEL_DOMAIN}" && -n "${XUI_MASK_DOMAIN}" && -n "${LETSENCRYPT_EMAIL}" ]]; then
    return
  fi

  [[ -t 0 ]] || fail "set XUI_* and LETSENCRYPT_EMAIL in .env first"

  XUI_PANEL_DOMAIN="$(prompt_domain "3x-ui panel domain" "${XUI_PANEL_DOMAIN}")"
  XUI_MASK_DOMAIN="$(prompt_domain "Mask domain (fake site)" "${XUI_MASK_DOMAIN}")"
  XUI_PANEL_PORT="$(prompt_text "3x-ui local panel port" "${XUI_PANEL_PORT}" 1)"
  LETSENCRYPT_EMAIL="$(prompt_text "Let's Encrypt email" "${LETSENCRYPT_EMAIL}" 1)"
}

resolve_ipv4() {
  getent ahostsv4 "$1" 2>/dev/null | awk '/STREAM/ {print $1; exit}'
}

server_ipv4() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

check_domain_points_to_server() {
  local domain="$1"
  local resolved_ip server_ip

  resolved_ip="$(resolve_ipv4 "${domain}" || true)"
  server_ip="$(server_ipv4 || true)"

  [[ -n "${server_ip}" ]] || fail "could not detect server IPv4"
  [[ -n "${resolved_ip}" ]] || fail "DNS for ${domain} is not ready"
  [[ "${resolved_ip}" == "${server_ip}" ]] || fail "${domain} resolves to ${resolved_ip}, server IP is ${server_ip}"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y ca-certificates curl docker.io docker-compose-v2 certbot ufw
  systemctl enable --now docker
}

install_3xui() {
  if command -v x-ui >/dev/null 2>&1; then
    log "3x-ui already installed, skip installer"
    return
  fi

  log "installing 3x-ui (official script)"
  bash <(curl -Ls "${XUI_INSTALL_URL}")
}

issue_certificates() {
  certbot certonly --standalone --non-interactive --agree-tos \
    -m "${LETSENCRYPT_EMAIL}" \
    -d "${XUI_PANEL_DOMAIN}" -d "${XUI_MASK_DOMAIN}" \
    --keep-until-expiring
}

render_angie_config() {
  local template="${REPO_DIR}/templates/angie.conf.tpl"
  local output="/opt/3xui-angie/angie.conf"

  sed \
    -e "s|__XUI_PANEL_DOMAIN__|${XUI_PANEL_DOMAIN}|g" \
    -e "s|__XUI_MASK_DOMAIN__|${XUI_MASK_DOMAIN}|g" \
    -e "s|__XUI_PANEL_PORT__|${XUI_PANEL_PORT}|g" \
    "${template}" >"${output}"
}

prepare_angie_stack() {
  install -d -m 0755 /opt/3xui-angie/mask
  install -d -m 0755 /opt/3xui-angie/certbot-webroot

  cat >/opt/3xui-angie/mask/index.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Welcome</title>
</head>
<body>
  <h1>It works</h1>
  <p>Service is running.</p>
</body>
</html>
EOF

  cat >/opt/3xui-angie/docker-compose.yml <<EOF
services:
  angie:
    image: docker.angie.software/angie:minimal
    container_name: xray-angie
    restart: unless-stopped
    network_mode: host
    volumes:
      - /opt/3xui-angie/angie.conf:/etc/angie/angie.conf:ro
      - /opt/3xui-angie/mask:/var/www/html:ro
      - /opt/3xui-angie/certbot-webroot:/var/www/certbot:ro
      - /etc/letsencrypt/live/${XUI_PANEL_DOMAIN}/fullchain.pem:/etc/nginx/ssl/${XUI_PANEL_DOMAIN}/fullchain.pem:ro
      - /etc/letsencrypt/live/${XUI_PANEL_DOMAIN}/privkey.pem:/etc/nginx/ssl/${XUI_PANEL_DOMAIN}/privkey.pem:ro
      - /etc/letsencrypt/live/${XUI_MASK_DOMAIN}/fullchain.pem:/etc/nginx/ssl/${XUI_MASK_DOMAIN}/fullchain.pem:ro
      - /etc/letsencrypt/live/${XUI_MASK_DOMAIN}/privkey.pem:/etc/nginx/ssl/${XUI_MASK_DOMAIN}/privkey.pem:ro
EOF

  render_angie_config
  docker compose -f /opt/3xui-angie/docker-compose.yml up -d
}

configure_firewall() {
  ufw allow 80/tcp
  ufw allow 443/tcp
}

print_summary() {
  cat <<EOF

[3xui-angie] installation finished

Panel URL (via Angie):
  https://${XUI_PANEL_DOMAIN}

Mask URL:
  https://${XUI_MASK_DOMAIN}

Important:
  1. In 3x-ui set panel listen to 127.0.0.1:${XUI_PANEL_PORT}
  2. Keep Cloudflare in DNS only mode for traffic domains
  3. Configure your inbounds in 3x-ui separately (this script only prepares panel/mask edge)
EOF
}

main() {
  require_root
  require_command curl
  require_command getent
  require_command sed

  load_env
  ensure_config
  check_domain_points_to_server "${XUI_PANEL_DOMAIN}"
  check_domain_points_to_server "${XUI_MASK_DOMAIN}"
  install_packages
  install_3xui
  issue_certificates
  prepare_angie_stack
  configure_firewall
  print_summary
}

main "$@"
