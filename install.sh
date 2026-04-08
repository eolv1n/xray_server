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
  APP_DIR="${APP_DIR:-/opt/xray_panel}"
  XRAY_UUID="${XRAY_UUID:-}"
  XRAY_PRIVATE_KEY="${XRAY_PRIVATE_KEY:-}"
  XRAY_PUBLIC_KEY="${XRAY_PUBLIC_KEY:-}"
  XRAY_SHORT_ID="${XRAY_SHORT_ID:-}"
  MARZBAN_USER="${MARZBAN_USER:-}"
  MARZBAN_PASS="${MARZBAN_PASS:-}"
  MARZBAN_DASHBOARD_PATH="${MARZBAN_DASHBOARD_PATH:-}"
  MARZBAN_SUBSCRIPTION_PATH="${MARZBAN_SUBSCRIPTION_PATH:-}"
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

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt_install ca-certificates curl unzip openssl sed gawk uuid-runtime docker.io docker-compose-v2
  systemctl enable docker
  systemctl start docker
}

docker_compose_cmd() {
  docker compose version >/dev/null 2>&1 || fail "docker compose plugin is missing"
  echo "docker compose"
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
  private_key="$(printf '%s\n' "${output}" | awk -F': ' '/Private key:|PrivateKey:/ {print $2; exit}')"
  public_key="$(printf '%s\n' "${output}" | awk -F': ' '/Public key:|Password \\(PublicKey\\):/ {print $2; exit}')"

  [[ -n "${private_key}" && -n "${public_key}" ]] || fail "failed to generate REALITY keys"
  printf '%s\n%s\n' "${private_key}" "${public_key}"
}

prepare_dirs() {
  install -d -m 0755 "${APP_DIR}"
  install -d -m 0755 "${APP_DIR}/marzban"
  install -d -m 0755 "${APP_DIR}/mask"
  install -d -m 0755 "${APP_DIR}/xray-core"
  install -d -m 0755 "${APP_DIR}/marzban_lib"
}

render_template() {
  local template_file="$1"
  local output_file="$2"
  shift 2
  sed "$@" "${template_file}" >"${output_file}"
}

sync_runtime_files() {
  install -m 0644 "${REPO_DIR}/docker-compose.yml" "${APP_DIR}/docker-compose.yml"
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
  render_template \
    "${REPO_DIR}/templates/xray.json.tpl" \
    "${APP_DIR}/marzban/xray_config.json" \
    -e "s|__XRAY_UUID__|${XRAY_UUID}|g" \
    -e "s|__EDGE_DOMAIN__|${EDGE_DOMAIN}|g" \
    -e "s|__PANEL_DOMAIN__|${PANEL_DOMAIN}|g" \
    -e "s|__XRAY_PRIVATE_KEY__|${XRAY_PRIVATE_KEY}|g" \
    -e "s|__XRAY_SHORT_ID__|${XRAY_SHORT_ID}|g"

  render_template \
    "${REPO_DIR}/templates/marzban.env.tpl" \
    "${APP_DIR}/marzban/.env" \
    -e "s|__MARZBAN_USER__|${MARZBAN_USER}|g" \
    -e "s|__MARZBAN_PASS__|${MARZBAN_PASS}|g" \
    -e "s|__MARZBAN_DASHBOARD_PATH__|${MARZBAN_DASHBOARD_PATH}|g" \
    -e "s|__PANEL_DOMAIN__|${PANEL_DOMAIN}|g" \
    -e "s|__MARZBAN_SUBSCRIPTION_PATH__|${MARZBAN_SUBSCRIPTION_PATH}|g"

  render_template \
    "${REPO_DIR}/templates/angie.conf.tpl" \
    "${APP_DIR}/angie.conf" \
    -e "s|__EDGE_DOMAIN__|${EDGE_DOMAIN}|g" \
    -e "s|__PANEL_DOMAIN__|${PANEL_DOMAIN}|g" \
    -e "s|__APP_DIR__|${APP_DIR}|g"

  install -m 0644 "${REPO_DIR}/templates/mask.html.tpl" "${APP_DIR}/mask/index.html"
}

write_runtime_env() {
  cat >"${APP_DIR}/.env" <<EOF
EDGE_DOMAIN=${EDGE_DOMAIN}
PANEL_DOMAIN=${PANEL_DOMAIN}
APP_DIR=${APP_DIR}
XRAY_UUID=${XRAY_UUID}
XRAY_PRIVATE_KEY=${XRAY_PRIVATE_KEY}
XRAY_PUBLIC_KEY=${XRAY_PUBLIC_KEY}
XRAY_SHORT_ID=${XRAY_SHORT_ID}
MARZBAN_USER=${MARZBAN_USER}
MARZBAN_PASS=${MARZBAN_PASS}
MARZBAN_DASHBOARD_PATH=${MARZBAN_DASHBOARD_PATH}
MARZBAN_SUBSCRIPTION_PATH=${MARZBAN_SUBSCRIPTION_PATH}
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
  REALITY / edge domain: ${EDGE_DOMAIN}
  Marzban panel domain: ${PANEL_DOMAIN}

Marzban:
  Admin user: ${MARZBAN_USER}
  Admin password: ${MARZBAN_PASS}
  Dashboard path: /${MARZBAN_DASHBOARD_PATH}/
  Subscription path: /${MARZBAN_SUBSCRIPTION_PATH}/

REALITY:
  UUID: ${XRAY_UUID}
  Public key: ${XRAY_PUBLIC_KEY}
  Short ID: ${XRAY_SHORT_ID}

Client link:
  vless://${XRAY_UUID}@${EDGE_DOMAIN}:443?type=tcp&security=reality&pbk=${XRAY_PUBLIC_KEY}&fp=chrome&sni=${EDGE_DOMAIN}&sid=${XRAY_SHORT_ID}&flow=xtls-rprx-vision#reality-main

Notes:
  1. First certificate issuance depends on both domains resolving to this VPS.
  2. Open https://${PANEL_DOMAIN}/${MARZBAN_DASHBOARD_PATH}/ to reach the panel.
  3. Re-run ./install.sh after changing .env to regenerate configs and restart the stack.
EOF
}

main() {
  require_root
  load_env
  ensure_configured
  ensure_base_packages
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
  print_summary
}

main "$@"
