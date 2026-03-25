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
APP_DIR="${APP_DIR:-/opt/xray_server}"
NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-8443}"
XRAY_XHTTP_PORT="${XRAY_XHTTP_PORT:-12777}"
XRAY_REALITY_PORT="${XRAY_REALITY_PORT:-12888}"
CLOAK_PORT="${CLOAK_PORT:-18080}"
XRAY_REALITY_SERVER_NAME="${XRAY_REALITY_SERVER_NAME:-www.microsoft.com}"
XRAY_REALITY_DEST="${XRAY_REALITY_DEST:-${XRAY_REALITY_SERVER_NAME}:443}"
XRAY_UUID="${XRAY_UUID:-}"
XRAY_XHTTP_PATH="${XRAY_XHTTP_PATH:-}"
XRAY_REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
XRAY_REALITY_SHORT_ID="${XRAY_REALITY_SHORT_ID:-}"

readonly REPO_DIR
readonly APP_DIR

log() {
  printf '[xray-server] %s\n' "$*"
}

fail() {
  printf '[xray-server] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "run install.sh as root"
  fi
}

ensure_domain() {
  [[ -n "${DOMAIN}" ]] || fail "set DOMAIN in .env before running install.sh"
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt_install ca-certificates curl gnupg lsb-release openssl sed gawk uuid-runtime
}

ensure_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    return
  fi

  log "installing nginx-full"
  apt_install nginx-full
  systemctl enable nginx
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi

  log "installing docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
}

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi

  fail "docker compose plugin is missing"
}

generate_uuid() {
  if [[ -n "${XRAY_UUID}" ]]; then
    echo "${XRAY_UUID}"
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

generate_xhttp_path() {
  if [[ -n "${XRAY_XHTTP_PATH}" ]]; then
    echo "${XRAY_XHTTP_PATH}"
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
    printf '\n'
  fi
}

generate_short_id() {
  if [[ -n "${XRAY_REALITY_SHORT_ID}" ]]; then
    echo "${XRAY_REALITY_SHORT_ID}"
  else
    openssl rand -hex 8
  fi
}

generate_reality_keys() {
  if [[ -n "${XRAY_REALITY_PRIVATE_KEY}" && -n "${XRAY_REALITY_PUBLIC_KEY}" ]]; then
    printf '%s\n%s\n' "${XRAY_REALITY_PRIVATE_KEY}" "${XRAY_REALITY_PUBLIC_KEY}"
    return
  fi

  local output private_key public_key
  output="$(docker run --rm ghcr.io/xtls/xray-core:latest x25519)"
  private_key="$(printf '%s\n' "${output}" | awk '/Private key:/ {print $3}')"
  public_key="$(printf '%s\n' "${output}" | awk '/Public key:/ {print $3}')"

  [[ -n "${private_key}" && -n "${public_key}" ]] || fail "failed to generate REALITY keys"
  printf '%s\n%s\n' "${private_key}" "${public_key}"
}

prepare_dirs() {
  install -d -m 0755 "${APP_DIR}"
  install -d -m 0755 "${APP_DIR}/config"
  install -d -m 0755 "${APP_DIR}/logs/xray"
  install -d -m 0755 "${APP_DIR}/data/filebrowser"
  install -d -m 0700 "${APP_DIR}/certs"
}

sync_repo_files() {
  install -m 0644 "${REPO_DIR}/docker-compose.yml" "${APP_DIR}/docker-compose.yml"
}

generate_tls_cert() {
  local cert_file key_file
  cert_file="${APP_DIR}/certs/origin.crt"
  key_file="${APP_DIR}/certs/origin.key"

  if [[ ! -s "${cert_file}" || ! -s "${key_file}" ]]; then
    log "generating self-signed origin certificate for ${DOMAIN}"
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout "${key_file}" \
      -out "${cert_file}" \
      -days 3650 \
      -subj "/CN=${DOMAIN}"
  fi

  printf '%s\n%s\n' "${cert_file}" "${key_file}"
}

render_template() {
  local template_file output_file
  template_file="$1"
  output_file="$2"
  shift 2

  sed "$@" "${template_file}" >"${output_file}"
}

generate_cloudflare_ips() {
  local v4_file v6_file output_file
  v4_file="$(mktemp)"
  v6_file="$(mktemp)"
  output_file="${APP_DIR}/config/cloudflare-ips.conf"

  curl -fsSL https://www.cloudflare.com/ips-v4 -o "${v4_file}"
  curl -fsSL https://www.cloudflare.com/ips-v6 -o "${v6_file}"

  {
    printf 'geo $remote_addr $is_cdn {\n'
    printf '    default 0;\n'
    awk '{printf "    %s 1;\n", $1}' "${v4_file}"
    awk '{printf "    %s 1;\n", $1}' "${v6_file}"
    printf '}\n'
  } >"${output_file}"

  rm -f "${v4_file}" "${v6_file}"
}

ensure_nginx_stream_include() {
  local nginx_conf include_line
  nginx_conf="/etc/nginx/nginx.conf"
  include_line="include /etc/nginx/stream-conf.d/*.conf;"

  install -d -m 0755 /etc/nginx/stream-conf.d

  if grep -Fq "${include_line}" "${nginx_conf}"; then
    return
  fi

  cp "${nginx_conf}" "${nginx_conf}.bak.$(date +%s)"
  printf '\nstream {\n    %s\n}\n' "${include_line}" >>"${nginx_conf}"
}

write_nginx_configs() {
  local cert_file key_file
  cert_file="$1"
  key_file="$2"

  render_template \
    "${REPO_DIR}/templates/nginx-http.conf.tpl" \
    "/etc/nginx/conf.d/xray-http.conf" \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__NGINX_HTTP_PORT__|${NGINX_HTTP_PORT}|g" \
    -e "s|__XRAY_XHTTP_PATH__|${XRAY_XHTTP_PATH}|g" \
    -e "s|__XRAY_XHTTP_PORT__|${XRAY_XHTTP_PORT}|g" \
    -e "s|__CLOAK_PORT__|${CLOAK_PORT}|g" \
    -e "s|__TLS_CERT__|${cert_file}|g" \
    -e "s|__TLS_KEY__|${key_file}|g"

  render_template \
    "${REPO_DIR}/templates/nginx-stream.conf.tpl" \
    "/etc/nginx/stream-conf.d/xray-stream.conf" \
    -e "s|__APP_DIR__|${APP_DIR}|g" \
    -e "s|__NGINX_HTTP_PORT__|${NGINX_HTTP_PORT}|g" \
    -e "s|__XRAY_REALITY_PORT__|${XRAY_REALITY_PORT}|g"
}

write_xray_config() {
  render_template \
    "${REPO_DIR}/templates/config.jsonc.tpl" \
    "${APP_DIR}/config/config.jsonc" \
    -e "s|__XRAY_UUID__|${XRAY_UUID}|g" \
    -e "s|__XRAY_XHTTP_PATH__|${XRAY_XHTTP_PATH}|g" \
    -e "s|__XRAY_REALITY_DEST__|${XRAY_REALITY_DEST}|g" \
    -e "s|__XRAY_REALITY_SERVER_NAME__|${XRAY_REALITY_SERVER_NAME}|g" \
    -e "s|__XRAY_REALITY_PRIVATE_KEY__|${XRAY_REALITY_PRIVATE_KEY}|g" \
    -e "s|__XRAY_REALITY_SHORT_ID__|${XRAY_REALITY_SHORT_ID}|g"
}

write_runtime_env() {
  cat >"${APP_DIR}/.env" <<EOF
DOMAIN=${DOMAIN}
XRAY_UUID=${XRAY_UUID}
XRAY_XHTTP_PATH=${XRAY_XHTTP_PATH}
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY}
XRAY_REALITY_PUBLIC_KEY=${XRAY_REALITY_PUBLIC_KEY}
XRAY_REALITY_SHORT_ID=${XRAY_REALITY_SHORT_ID}
XRAY_REALITY_SERVER_NAME=${XRAY_REALITY_SERVER_NAME}
XRAY_REALITY_DEST=${XRAY_REALITY_DEST}
NGINX_HTTP_PORT=${NGINX_HTTP_PORT}
XRAY_XHTTP_PORT=${XRAY_XHTTP_PORT}
XRAY_REALITY_PORT=${XRAY_REALITY_PORT}
CLOAK_PORT=${CLOAK_PORT}
EOF
  chmod 0600 "${APP_DIR}/.env"
}

restart_nginx() {
  nginx -t
  systemctl restart nginx
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

detect_reality_endpoint() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

print_summary() {
  local endpoint
  endpoint="$(detect_reality_endpoint || true)"

  cat <<EOF

Installation complete.

Files:
  App directory: ${APP_DIR}
  Xray config: ${APP_DIR}/config/config.jsonc
  Nginx HTTP config: /etc/nginx/conf.d/xray-http.conf
  Nginx stream config: /etc/nginx/stream-conf.d/xray-stream.conf

Client values:
  Domain (XHTTP over CDN): ${DOMAIN}
  UUID: ${XRAY_UUID}
  XHTTP path: ${XRAY_XHTTP_PATH}
  REALITY endpoint: ${endpoint:-<server-ip>}
  REALITY serverName/SNI: ${XRAY_REALITY_SERVER_NAME}
  REALITY public key: ${XRAY_REALITY_PUBLIC_KEY}
  REALITY shortId: ${XRAY_REALITY_SHORT_ID}

Notes:
  1. In Cloudflare, keep the ${DOMAIN} record proxied and enable gRPC.
  2. For REALITY, use the server IP or a separate DNS record that is not proxied by Cloudflare.
  3. Re-run ./install.sh after changing .env to regenerate configs and restart the stack.
EOF
}

main() {
  require_root
  ensure_domain
  ensure_base_packages
  ensure_nginx
  ensure_docker
  prepare_dirs
  sync_repo_files

  XRAY_UUID="$(generate_uuid)"
  XRAY_XHTTP_PATH="$(generate_xhttp_path)"
  XRAY_REALITY_SHORT_ID="$(generate_short_id)"
  mapfile -t reality_keys < <(generate_reality_keys)
  XRAY_REALITY_PRIVATE_KEY="${reality_keys[0]}"
  XRAY_REALITY_PUBLIC_KEY="${reality_keys[1]}"

  mapfile -t tls_paths < <(generate_tls_cert)
  generate_cloudflare_ips
  write_xray_config
  write_runtime_env
  ensure_nginx_stream_include
  write_nginx_configs "${tls_paths[0]}" "${tls_paths[1]}"
  restart_nginx
  start_stack
  print_summary
}

main "$@"
