#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"

readonly REPO_DIR

log() {
  printf '[xray-install] %s\n' "$*"
}

fail() {
  printf '[xray-install] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "run install.sh as root"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  elif [[ -f "${EXAMPLE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${EXAMPLE_ENV_FILE}"
  fi

  EDGE_DOMAIN="${EDGE_DOMAIN:-}"
  PANEL_DOMAIN="${PANEL_DOMAIN:-}"
  APP_DIR="${APP_DIR:-/opt/silentbridge}"
  PANEL_PORT="${PANEL_PORT:-8443}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.cloudflare.com}"
  REALITY_DEST="${REALITY_DEST:-www.cloudflare.com:443}"
  REALITY_ADDRESS="${REALITY_ADDRESS:-}"
  XRAY_UUID="${XRAY_UUID:-}"
  XRAY_PRIVATE_KEY="${XRAY_PRIVATE_KEY:-}"
  XRAY_PUBLIC_KEY="${XRAY_PUBLIC_KEY:-}"
  XRAY_SHORT_ID="${XRAY_SHORT_ID:-}"
  MARZBAN_USER="${MARZBAN_USER:-}"
  MARZBAN_PASS="${MARZBAN_PASS:-}"
  MARZBAN_DASHBOARD_PATH="${MARZBAN_DASHBOARD_PATH:-}"
  MARZBAN_SUBSCRIPTION_PATH="${MARZBAN_SUBSCRIPTION_PATH:-}"
  PANEL_ALLOWLIST="${PANEL_ALLOWLIST:-127.0.0.1/32}"
  XRAY_CORE_VERSION="${XRAY_CORE_VERSION:-26.2.6}"
  XRAY_IMAGE_TAG="${XRAY_IMAGE_TAG:-26.3.27}"
  MARZBAN_IMAGE="${MARZBAN_IMAGE:-gozargah/marzban:latest}"
}

ensure_configured() {
  if [[ -n "${EDGE_DOMAIN}" && -n "${PANEL_DOMAIN}" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    fail "EDGE_DOMAIN and PANEL_DOMAIN must be set. Run ./configure.sh first or create .env manually"
  fi

  log "launching interactive configuration wizard"
  bash "${REPO_DIR}/configure.sh"
  load_env

  [[ -n "${EDGE_DOMAIN}" && -n "${PANEL_DOMAIN}" ]] || fail "set EDGE_DOMAIN and PANEL_DOMAIN in .env before running install.sh"
}

confirm() {
  local prompt="$1"
  local answer

  if [[ ! -t 0 ]]; then
    return 1
  fi

  read -r -p "${prompt} [y/N]: " answer
  [[ "${answer,,}" == "y" ]]
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt_install ca-certificates curl unzip openssl sed gawk uuid-runtime docker.io docker-compose-v2 dnsutils
  systemctl enable docker
  systemctl start docker
}

docker_compose_cmd() {
  docker compose version >/dev/null 2>&1 || fail "docker compose plugin is missing"
  echo "docker compose"
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

  [[ -n "${server_ip}" ]] || fail "could not detect server IPv4 address"

  if [[ -z "${resolved_ip}" ]]; then
    log "warning: ${domain} has no resolvable IPv4 yet"
    if confirm "continue without IPv4 DNS confirmation for ${domain}?"; then
      return
    fi
    fail "DNS for ${domain} is not ready"
  fi

  if [[ "${resolved_ip}" != "${server_ip}" ]]; then
    log "warning: ${domain} resolves to ${resolved_ip}, but this server is ${server_ip}"
    if confirm "continue anyway with mismatched DNS for ${domain}?"; then
      return
    fi
    fail "DNS mismatch for ${domain}"
  fi
}

check_port_available() {
  local port="$1"
  local app_dir="${2:-}"
  local listeners

  listeners="$(ss -ltnp "( sport = :${port} )" 2>/dev/null | sed -n '2,120p' || true)"
  [[ -z "${listeners}" ]] && return

  if [[ -n "${app_dir}" ]]; then
    if printf '%s\n' "${listeners}" | grep -Fq "${app_dir}"; then
      return
    fi
    if printf '%s\n' "${listeners}" | grep -Eq 'docker-proxy|xray|angie|marzban'; then
      log "port ${port} is already in use by an existing stack"
      return
    fi
  fi

  printf '%s\n' "${listeners}" >&2
  fail "port ${port} is already busy"
}

ensure_runtime_prereqs() {
  require_command ss
  require_command curl
  require_command docker
  require_command getent

  check_domain_points_to_server "${EDGE_DOMAIN}"
  check_domain_points_to_server "${PANEL_DOMAIN}"
  check_port_available 80 "${APP_DIR}"
  check_port_available 443 "${APP_DIR}"
  check_port_available "${PANEL_PORT}" "${APP_DIR}"
}

generate_uuid() {
  [[ -n "${XRAY_UUID}" ]] && printf '%s\n' "${XRAY_UUID}" || cat /proc/sys/kernel/random/uuid
}

generate_short_id() {
  [[ -n "${XRAY_SHORT_ID}" ]] && printf '%s\n' "${XRAY_SHORT_ID}" || openssl rand -hex 8
}

generate_secret_slug() {
  openssl rand -hex 8
}

generate_password() {
  openssl rand -hex 9
  printf '\n'
}

generate_user() {
  printf 'admin-%s\n' "$(openssl rand -hex 3)"
}

generate_reality_keys() {
  if [[ -n "${XRAY_PRIVATE_KEY}" && -n "${XRAY_PUBLIC_KEY}" ]]; then
    printf '%s\n%s\n' "${XRAY_PRIVATE_KEY}" "${XRAY_PUBLIC_KEY}"
    return
  fi

  local output private_key public_key
  output="$(docker run --rm "ghcr.io/xtls/xray-core:${XRAY_IMAGE_TAG}" x25519)"
  private_key="$(printf '%s\n' "${output}" | sed -nE 's/^Private(Key| key):[[:space:]]*//p' | head -n 1)"
  public_key="$(printf '%s\n' "${output}" | sed -nE 's/^(Public key|Password \(PublicKey\)):[[:space:]]*//p' | head -n 1)"

  [[ -n "${private_key}" && -n "${public_key}" ]] || fail "failed to generate REALITY keys"
  printf '%s\n%s\n' "${private_key}" "${public_key}"
}

prepare_dirs() {
  install -d -m 0755 "${APP_DIR}"
  install -d -m 0755 "${APP_DIR}/marzban"
  install -d -m 0755 "${APP_DIR}/mask"
  install -d -m 0755 "${APP_DIR}/xray-core"
  install -d -m 0755 "${APP_DIR}/marzban_lib"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates/subscription"
}

build_panel_allowlist_rules() {
  local raw_list="${PANEL_ALLOWLIST:-}"
  local item trimmed output=""

  if [[ -z "${raw_list// }" ]]; then
    printf '%s\n' ""
    return
  fi

  IFS=',' read -r -a allow_items <<<"${raw_list}"
  for item in "${allow_items[@]}"; do
    trimmed="$(printf '%s' "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "${trimmed}" ]] || continue
    output="${output}allow ${trimmed};"$'\n'
  done

  output="${output}deny all;"
  printf '%s\n' "${output}"
}

render_template() {
  local template_file="$1"
  local output_file="$2"
  shift 2
  sed "$@" "${template_file}" >"${output_file}"
}

panel_port_suffix() {
  if [[ "${PANEL_PORT}" == "443" ]]; then
    printf '%s' ""
  else
    printf ':%s' "${PANEL_PORT}"
  fi
}

sync_runtime_files() {
  install -m 0644 "${REPO_DIR}/docker-compose.yml" "${APP_DIR}/docker-compose.yml"
}

warn_if_legacy_app_dir_exists() {
  local legacy_app_dir="/opt/silentbridge"

  if [[ "${APP_DIR}" == "${legacy_app_dir}" ]]; then
    return
  fi

  if [[ -d "${legacy_app_dir}" && ! -L "${legacy_app_dir}" ]]; then
    log "legacy install directory detected at ${legacy_app_dir}"
    if [[ ! -d "${APP_DIR}" || -z "$(find "${APP_DIR}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
      log "current install directory is ${APP_DIR}; review whether you want to migrate files before re-running install.sh"
    fi
  fi
}

download_xray_core() {
  local archive_name archive_url tmp_zip

  case "$(dpkg --print-architecture)" in
    amd64) archive_name="Xray-linux-64.zip" ;;
    arm64) archive_name="Xray-linux-arm64-v8a.zip" ;;
    *) fail "unsupported architecture: $(dpkg --print-architecture)" ;;
  esac

  archive_url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_CORE_VERSION}/${archive_name}"
  tmp_zip="$(mktemp)"

  log "downloading Xray-core v${XRAY_CORE_VERSION}"
  curl -fsSL "${archive_url}" -o "${tmp_zip}"
  rm -rf "${APP_DIR}/xray-core"/*
  unzip -qo "${tmp_zip}" -d "${APP_DIR}/xray-core"
  rm -f "${tmp_zip}"
}

write_configs() {
  local panel_allowlist_rules tmp_allowlist panel_port_suffix_value reality_address_value

  panel_allowlist_rules="$(build_panel_allowlist_rules)"
  tmp_allowlist="$(mktemp)"
  printf '%s\n' "${panel_allowlist_rules}" >"${tmp_allowlist}"
  panel_port_suffix_value="$(panel_port_suffix)"
  reality_address_value="${REALITY_ADDRESS:-$(server_ipv4)}"

  render_template \
    "${REPO_DIR}/templates/xray.json.tpl" \
    "${APP_DIR}/marzban/xray_config.json" \
    -e "s|__REALITY_DEST__|${REALITY_DEST}|g" \
    -e "s|__REALITY_SERVER_NAME__|${REALITY_SERVER_NAME}|g" \
    -e "s|__XRAY_PRIVATE_KEY__|${XRAY_PRIVATE_KEY}|g" \
    -e "s|__XRAY_SHORT_ID__|${XRAY_SHORT_ID}|g"

  render_template \
    "${REPO_DIR}/templates/marzban.env.tpl" \
    "${APP_DIR}/marzban/.env" \
    -e "s|__MARZBAN_USER__|${MARZBAN_USER}|g" \
    -e "s|__MARZBAN_PASS__|${MARZBAN_PASS}|g" \
    -e "s|__MARZBAN_DASHBOARD_PATH__|${MARZBAN_DASHBOARD_PATH}|g" \
    -e "s|__PANEL_DOMAIN__|${PANEL_DOMAIN}|g" \
    -e "s|__PANEL_PORT_SUFFIX__|${panel_port_suffix_value}|g" \
    -e "s|__MARZBAN_SUBSCRIPTION_PATH__|${MARZBAN_SUBSCRIPTION_PATH}|g"

  render_template \
    "${REPO_DIR}/templates/angie.conf.tpl" \
    "${APP_DIR}/angie.conf" \
    -e "s|__PANEL_DOMAIN__|${PANEL_DOMAIN}|g" \
    -e "s|__PANEL_PORT__|${PANEL_PORT}|g" \
    -e "s|__MARZBAN_DASHBOARD_PATH__|${MARZBAN_DASHBOARD_PATH}|g"

  python3 - "${APP_DIR}/angie.conf" "${tmp_allowlist}" <<'PY'
from pathlib import Path
import sys

conf_path = Path(sys.argv[1])
rules_path = Path(sys.argv[2])
content = conf_path.read_text()
rules = rules_path.read_text().rstrip("\n")
conf_path.write_text(content.replace("__PANEL_ALLOWLIST_RULES__", rules))
PY
  rm -f "${tmp_allowlist}"

  install -m 0644 "${REPO_DIR}/templates/mask.html.tpl" "${APP_DIR}/mask/index.html"
  install -m 0644 "${REPO_DIR}/templates/subscription-index.html.tpl" "${APP_DIR}/marzban_lib/templates/subscription/index.html"
}

write_runtime_env() {
  cat >"${APP_DIR}/.env" <<EOF
EDGE_DOMAIN=${EDGE_DOMAIN}
PANEL_DOMAIN=${PANEL_DOMAIN}
APP_DIR=${APP_DIR}
PANEL_PORT=${PANEL_PORT}
REALITY_SERVER_NAME=${REALITY_SERVER_NAME}
REALITY_DEST=${REALITY_DEST}
REALITY_ADDRESS=${REALITY_ADDRESS}
XRAY_UUID=${XRAY_UUID}
XRAY_PRIVATE_KEY=${XRAY_PRIVATE_KEY}
XRAY_PUBLIC_KEY=${XRAY_PUBLIC_KEY}
XRAY_SHORT_ID=${XRAY_SHORT_ID}
MARZBAN_USER=${MARZBAN_USER}
MARZBAN_PASS=${MARZBAN_PASS}
MARZBAN_DASHBOARD_PATH=${MARZBAN_DASHBOARD_PATH}
MARZBAN_SUBSCRIPTION_PATH=${MARZBAN_SUBSCRIPTION_PATH}
PANEL_ALLOWLIST=${PANEL_ALLOWLIST}
XRAY_CORE_VERSION=${XRAY_CORE_VERSION}
XRAY_IMAGE_TAG=${XRAY_IMAGE_TAG}
MARZBAN_IMAGE=${MARZBAN_IMAGE}
EOF
  chmod 0600 "${APP_DIR}/.env"
}

start_stack() {
  local compose_cmd
  compose_cmd="$(docker_compose_cmd)"
  (
    cd "${APP_DIR}"
    ${compose_cmd} pull
    ${compose_cmd} up -d
  )
}

wait_for_panel_api() {
  local attempt max_attempts=30 socket_path panel_url
  socket_path="${APP_DIR}/marzban_lib/marzban.socket"
  panel_url="http://localhost/api/system"

  for attempt in $(seq 1 "${max_attempts}"); do
    if [[ -S "${socket_path}" ]] && curl -sSf --unix-socket "${socket_path}" "${panel_url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  fail "panel API did not become ready on ${socket_path}"
}

configure_marzban_hosts() {
  local token token_url hosts_url payload address_json sni_json socket_path

  socket_path="${APP_DIR}/marzban_lib/marzban.socket"
  address_json="$(json_escape "${REALITY_ADDRESS:-$(server_ipv4)}")"
  sni_json="$(json_escape "${REALITY_SERVER_NAME}")"
  wait_for_panel_api

  token_url="http://localhost/api/admin/token"
  hosts_url="http://localhost/api/hosts"

  token="$(
    curl -sSf --unix-socket "${socket_path}" -X POST "${token_url}" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "username=${MARZBAN_USER}" \
      --data-urlencode "password=${MARZBAN_PASS}" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
  )"

  payload="$(cat <<EOF
{"VLESS TCP VISION REALITY":[{"remark":"🚀 Marz ({USERNAME}) [{PROTOCOL} - {TRANSPORT}]","address":${address_json},"port":443,"sni":${sni_json},"host":null,"path":null,"security":"inbound_default","alpn":"","fingerprint":"chrome","allowinsecure":false,"is_disabled":false,"mux_enable":false,"fragment_setting":null,"noise_setting":null,"random_user_agent":false,"use_sni_as_host":false}]}
EOF
)"

  curl -sSf --unix-socket "${socket_path}" -X PUT "${hosts_url}" \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' \
    --data "${payload}" >/dev/null
}

show_post_install_checks() {
  cat <<EOF

Recommended checks:
  docker ps
  docker logs --tail 50 xray-angie
  docker logs --tail 50 xray-marzban
  curl -kI https://${PANEL_DOMAIN}:$(printf '%s' "${PANEL_PORT}")
EOF
}

print_summary() {
  cat <<EOF

Installation complete.

Files:
  App directory: ${APP_DIR}
  Compose file: ${APP_DIR}/docker-compose.yml
  Angie config: ${APP_DIR}/angie.conf
  Marzban env: ${APP_DIR}/marzban/.env
  Xray config: ${APP_DIR}/marzban/xray_config.json

Domains:
  REALITY address: ${REALITY_ADDRESS:-$(server_ipv4)}
  REALITY SNI: ${REALITY_SERVER_NAME}
  REALITY fallback dest: ${REALITY_DEST}
  Marzban panel domain: ${PANEL_DOMAIN}
  Marzban panel port: ${PANEL_PORT}

Marzban:
  Admin user: ${MARZBAN_USER}
  Admin password: ${MARZBAN_PASS}
  Dashboard path: /${MARZBAN_DASHBOARD_PATH}/
  Subscription path: /${MARZBAN_SUBSCRIPTION_PATH}/
  Panel allowlist: ${PANEL_ALLOWLIST}

REALITY:
  Public key: ${XRAY_PUBLIC_KEY}
  Short ID: ${XRAY_SHORT_ID}

Notes:
  1. First certificate issuance depends on both domains resolving to this VPS.
  2. Open https://${PANEL_DOMAIN}$(panel_port_suffix)/${MARZBAN_DASHBOARD_PATH}/ to reach the panel.
  3. The panel root path returns 404 and panel responses are marked noindex.
  4. Client links are generated by Marzban and should use the server IP plus the REALITY SNI above.
  5. Re-run ./install.sh after changing .env to regenerate configs and restart the stack.
EOF
}

main() {
  require_root
  load_env
  ensure_configured
  ensure_base_packages
  ensure_runtime_prereqs
  warn_if_legacy_app_dir_exists
  prepare_dirs
  sync_runtime_files

  XRAY_UUID="$(generate_uuid)"
  XRAY_SHORT_ID="$(generate_short_id)"
  MARZBAN_USER="${MARZBAN_USER:-$(generate_user)}"
  MARZBAN_PASS="${MARZBAN_PASS:-$(generate_password)}"
  MARZBAN_DASHBOARD_PATH="${MARZBAN_DASHBOARD_PATH:-$(generate_secret_slug)}"
  MARZBAN_SUBSCRIPTION_PATH="${MARZBAN_SUBSCRIPTION_PATH:-$(generate_secret_slug)}"
  mapfile -t reality_keys < <(generate_reality_keys)
  XRAY_PRIVATE_KEY="${reality_keys[0]}"
  XRAY_PUBLIC_KEY="${reality_keys[1]}"

  download_xray_core
  write_configs
  write_runtime_env
  start_stack
  configure_marzban_hosts
  print_summary
  show_post_install_checks
}

main "$@"
