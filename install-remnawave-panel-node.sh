#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"

log() {
  printf '[remnawave-panel-node] %s\n' "$*"
}

fail() {
  printf '[remnawave-panel-node] error: %s\n' "$*" >&2
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

  REMNAWAVE_PANEL_DOMAIN="${REMNAWAVE_PANEL_DOMAIN:-}"
  REMNAWAVE_SUB_DOMAIN="${REMNAWAVE_SUB_DOMAIN:-}"
  REMNAWAVE_NODE_DOMAIN="${REMNAWAVE_NODE_DOMAIN:-}"
  LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
  REMNAWAVE_UPSTREAM_REPO="${REMNAWAVE_UPSTREAM_REPO:-https://github.com/eGamesAPI/remnawave-reverse-proxy.git}"
  REMNAWAVE_CLONE_DIR="${REMNAWAVE_CLONE_DIR:-/usr/local/src/remnawave-reverse-proxy}"
  REMNAWAVE_SCRIPT_LANGUAGE="${REMNAWAVE_SCRIPT_LANGUAGE:-ru}"
  REMNAWAVE_USE_IMAGE_MIRRORS="${REMNAWAVE_USE_IMAGE_MIRRORS:-0}"
  REMNAWAVE_INSTALL_LEGIZ_ORION="${REMNAWAVE_INSTALL_LEGIZ_ORION:-1}"
  REMNAWAVE_BACKEND_IMAGE="${REMNAWAVE_BACKEND_IMAGE:-ghcr.io/remnawave/backend:2}"
  REMNAWAVE_POSTGRES_IMAGE="${REMNAWAVE_POSTGRES_IMAGE:-public.ecr.aws/docker/library/postgres:18.3}"
  REMNAWAVE_VALKEY_IMAGE="${REMNAWAVE_VALKEY_IMAGE:-ghcr.io/valkey-io/valkey:9.0.3-alpine}"
  REMNAWAVE_NGINX_IMAGE="${REMNAWAVE_NGINX_IMAGE:-public.ecr.aws/docker/library/nginx:1.28}"
  REMNAWAVE_NODE_IMAGE="${REMNAWAVE_NODE_IMAGE:-}"
  REMNAWAVE_SUBSCRIPTION_PAGE_IMAGE="${REMNAWAVE_SUBSCRIPTION_PAGE_IMAGE:-}"
}

ensure_config() {
  if [[ -n "${REMNAWAVE_PANEL_DOMAIN}" && -n "${REMNAWAVE_SUB_DOMAIN}" && -n "${REMNAWAVE_NODE_DOMAIN}" && -n "${LETSENCRYPT_EMAIL}" ]]; then
    return
  fi

  [[ -t 0 ]] || fail "set REMNAWAVE_* values in .env first"

  REMNAWAVE_PANEL_DOMAIN="$(prompt_domain "Panel domain" "${REMNAWAVE_PANEL_DOMAIN}")"
  REMNAWAVE_SUB_DOMAIN="$(prompt_domain "Subscription domain" "${REMNAWAVE_SUB_DOMAIN}")"
  REMNAWAVE_NODE_DOMAIN="$(prompt_domain "Node/selfsteal domain" "${REMNAWAVE_NODE_DOMAIN}")"
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

prepare_upstream_repo() {
  if [[ -d "${REMNAWAVE_CLONE_DIR}/.git" ]]; then
    git -C "${REMNAWAVE_CLONE_DIR}" fetch --all --tags
    git -C "${REMNAWAVE_CLONE_DIR}" reset --hard origin/main
  else
    rm -rf "${REMNAWAVE_CLONE_DIR}"
    git clone "${REMNAWAVE_UPSTREAM_REPO}" "${REMNAWAVE_CLONE_DIR}"
  fi
}

patch_upstream_for_os() {
  if grep -q 'plucky' /etc/os-release; then
    perl -0pi -e 's/grep -q "noble" \/etc\/os-release && ! grep -q "trixie"/grep -q "noble" \/etc\/os-release && ! grep -q "plucky" \/etc\/os-release && ! grep -q "trixie"/' \
      "${REMNAWAVE_CLONE_DIR}/install_remnawave.sh"
  fi
}

is_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

patch_image_in_upstream() {
  local old_image="$1"
  local new_image="$2"
  local file

  [[ -n "${new_image}" && "${old_image}" != "${new_image}" ]] || return

  while IFS= read -r -d '' file; do
    OLD_IMAGE="${old_image}" NEW_IMAGE="${new_image}" perl -0pi -e \
      's/(image:\s*)\Q$ENV{OLD_IMAGE}\E/${1}$ENV{NEW_IMAGE}/g' "${file}"
  done < <(find "${REMNAWAVE_CLONE_DIR}/src" -type f -name '*.sh' -print0)
}

patch_upstream_images() {
  is_enabled "${REMNAWAVE_USE_IMAGE_MIRRORS}" || return

  log "patching upstream image names to reduce Docker Hub pulls"
  patch_image_in_upstream "remnawave/backend:2" "${REMNAWAVE_BACKEND_IMAGE}"
  patch_image_in_upstream "postgres:18.3" "${REMNAWAVE_POSTGRES_IMAGE}"
  patch_image_in_upstream "valkey/valkey:9.0.3-alpine" "${REMNAWAVE_VALKEY_IMAGE}"
  patch_image_in_upstream "nginx:1.28" "${REMNAWAVE_NGINX_IMAGE}"
  patch_image_in_upstream "remnawave/node:latest" "${REMNAWAVE_NODE_IMAGE}"
  patch_image_in_upstream "remnawave/subscription-page:latest" "${REMNAWAVE_SUBSCRIPTION_PAGE_IMAGE}"
}

language_prefix() {
  local selected_file="/usr/local/remnawave_reverse/selected_language"

  if [[ -f "${selected_file}" ]]; then
    return
  fi

  case "${REMNAWAVE_SCRIPT_LANGUAGE}" in
    ru) printf '2\n' ;;
    en) printf '1\n' ;;
    *) fail "unsupported REMNAWAVE_SCRIPT_LANGUAGE: ${REMNAWAVE_SCRIPT_LANGUAGE}" ;;
  esac
}

run_installer() {
  cd "${REMNAWAVE_CLONE_DIR}"
  {
    language_prefix
    printf '1\n'
    printf '1\n'
    printf 'y\n'
    printf '1\n'
    printf '%s\n' "${REMNAWAVE_PANEL_DOMAIN}"
    printf '%s\n' "${REMNAWAVE_SUB_DOMAIN}"
    printf '%s\n' "${REMNAWAVE_NODE_DOMAIN}"
    printf '2\n'
    printf '%s\n' "${LETSENCRYPT_EMAIL}"
  } | bash ./install_remnawave.sh
}

install_yq_if_missing() {
  if command -v yq >/dev/null 2>&1; then
    return
  fi

  log "installing yq for compose edits"
  wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
  chmod +x /usr/bin/yq
}

install_legiz_orion() {
  local target_dir="/opt/remnawave"
  local compose_file="${target_dir}/docker-compose.yml"
  local index_file="${target_dir}/index.html"

  is_enabled "${REMNAWAVE_INSTALL_LEGIZ_ORION}" || return

  [[ -f "${compose_file}" ]] || fail "Remnawave compose file not found: ${compose_file}"
  command -v curl >/dev/null 2>&1 || fail "required command is missing: curl"
  install_yq_if_missing

  log "installing legiz Orion subscription page"
  rm -f "${target_dir}/app-config.json" "${index_file}"
  if ! curl -fsSL https://raw.githubusercontent.com/legiz-ru/Orion/refs/heads/main/index.html -o "${index_file}"; then
    curl -fsSL https://cdn.jsdelivr.net/gh/legiz-ru/Orion@main/index.html -o "${index_file}"
  fi

  yq eval 'del(.services."remnawave-subscription-page".volumes)' -i "${compose_file}"
  yq eval '.services."remnawave-subscription-page".volumes += ["./index.html:/opt/app/frontend/index.html"]' -i "${compose_file}"
  yq eval -i '... comments=""' "${compose_file}"

  (cd "${target_dir}" && docker compose up -d remnawave-subscription-page)
}

extract_secret_panel_url() {
  local log_file="$1"
  grep -Eo "https://${REMNAWAVE_PANEL_DOMAIN}/auth/login\\?[^[:space:]]+" "${log_file}" | tail -n 1 || true
}

post_install_checks() {
  local log_file="/usr/local/remnawave_reverse/remnawave_reverse.log"
  local panel_url panel_secret_query admin_user admin_pass payload status_code

  panel_url="$(extract_secret_panel_url "${log_file}")"
  panel_secret_query=""
  if [[ "${panel_url}" == *\?* ]]; then
    panel_secret_query="?${panel_url#*\?}"
  fi
  admin_user="$(grep -E '^(Логин:|Username:)' "${log_file}" | tail -n 1 | sed -E 's/^(Логин:|Username:)[[:space:]]*//')"
  admin_pass="$(grep -E '^(Пароль:|Password:)' "${log_file}" | tail -n 1 | sed -E 's/^(Пароль:|Password:)[[:space:]]*//')"

  if [[ -n "${panel_url}" ]]; then
    log "checking panel frontend"
    curl -kfsSI --max-time 20 "${panel_url}" >/dev/null || log "warning: panel frontend check failed"
  fi

  if [[ -n "${admin_user}" && -n "${admin_pass}" ]] && command -v jq >/dev/null 2>&1; then
    log "checking admin login"
    payload="$(jq -n --arg username "${admin_user}" --arg password "${admin_pass}" '{username:$username,password:$password}')"
    status_code="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' \
      -H 'Content-Type: application/json' \
      -X POST "https://${REMNAWAVE_PANEL_DOMAIN}/api/auth/login${panel_secret_query}" \
      --data "${payload}" || true)"
    [[ "${status_code}" == "200" ]] || log "warning: admin login check returned HTTP ${status_code}"
  fi

  if [[ -f /opt/remnawave/docker-compose.yml ]]; then
    log "checking containers"
    docker compose -f /opt/remnawave/docker-compose.yml ps
  fi
}

print_summary() {
  local log_file="/usr/local/remnawave_reverse/remnawave_reverse.log"

  printf '\n'
  log "installation finished"
  log "panel url:"
  grep -F 'https://' "${log_file}" | tail -n 1 || true
  log "admin credentials:"
  grep -E '^(Логин:|Пароль:|Username:|Password:)' "${log_file}" | tail -n 4 || true
}

main() {
  require_root
  require_command git
  require_command perl
  require_command getent

  load_env
  ensure_config

  check_domain_points_to_server "${REMNAWAVE_PANEL_DOMAIN}"
  check_domain_points_to_server "${REMNAWAVE_SUB_DOMAIN}"
  check_domain_points_to_server "${REMNAWAVE_NODE_DOMAIN}"

  prepare_upstream_repo
  patch_upstream_for_os
  patch_upstream_images
  run_installer
  install_legiz_orion
  post_install_checks
  print_summary
}

main "$@"
