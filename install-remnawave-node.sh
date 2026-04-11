#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"

log() {
  printf '[remnawave-node] %s\n' "$*"
}

fail() {
  printf '[remnawave-node] error: %s\n' "$*" >&2
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

validate_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
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

prompt_ipv4() {
  local label="$1"
  local current="$2"
  local value

  while true; do
    value="$(prompt_text "${label}" "${current}" 1)"
    if validate_ipv4 "${value}"; then
      printf '%s' "${value}"
      return
    fi
    log "enter a valid IPv4 address"
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

  REMNAWAVE_NODE_DOMAIN="${REMNAWAVE_NODE_DOMAIN:-}"
  REMNAWAVE_PANEL_IP="${REMNAWAVE_PANEL_IP:-}"
  REMNAWAVE_NODE_SECRET_KEY="${REMNAWAVE_NODE_SECRET_KEY:-}"
  REMNAWAVE_NODE_SECRET_KEY_FILE="${REMNAWAVE_NODE_SECRET_KEY_FILE:-}"
  LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
  REMNAWAVE_UPSTREAM_REPO="${REMNAWAVE_UPSTREAM_REPO:-https://github.com/eGamesAPI/remnawave-reverse-proxy.git}"
  REMNAWAVE_CLONE_DIR="${REMNAWAVE_CLONE_DIR:-/usr/local/src/remnawave-reverse-proxy}"
  REMNAWAVE_SCRIPT_LANGUAGE="${REMNAWAVE_SCRIPT_LANGUAGE:-ru}"
}

ensure_config() {
  if [[ -z "${REMNAWAVE_NODE_DOMAIN}" ]]; then
    [[ -t 0 ]] || fail "set REMNAWAVE_NODE_DOMAIN in .env first"
    REMNAWAVE_NODE_DOMAIN="$(prompt_domain "Node/selfsteal domain" "${REMNAWAVE_NODE_DOMAIN}")"
  fi

  if [[ -z "${REMNAWAVE_PANEL_IP}" ]]; then
    [[ -t 0 ]] || fail "set REMNAWAVE_PANEL_IP in .env first"
    REMNAWAVE_PANEL_IP="$(prompt_ipv4 "Panel server IPv4" "${REMNAWAVE_PANEL_IP}")"
  fi

  if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
    [[ -t 0 ]] || fail "set LETSENCRYPT_EMAIL in .env first"
    LETSENCRYPT_EMAIL="$(prompt_text "Let's Encrypt email" "${LETSENCRYPT_EMAIL}" 1)"
  fi
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

load_node_secret() {
  if [[ -n "${REMNAWAVE_NODE_SECRET_KEY_FILE}" ]]; then
    [[ -f "${REMNAWAVE_NODE_SECRET_KEY_FILE}" ]] || fail "secret key file not found: ${REMNAWAVE_NODE_SECRET_KEY_FILE}"
    cat "${REMNAWAVE_NODE_SECRET_KEY_FILE}"
    return
  fi

  if [[ -n "${REMNAWAVE_NODE_SECRET_KEY}" ]]; then
    printf '%b' "${REMNAWAVE_NODE_SECRET_KEY}"
    return
  fi

  fail "set REMNAWAVE_NODE_SECRET_KEY_FILE or REMNAWAVE_NODE_SECRET_KEY"
}

run_installer() {
  local node_secret
  node_secret="$(load_node_secret)"

  cd "${REMNAWAVE_CLONE_DIR}"
  {
    language_prefix
    printf '1\n'
    printf '4\n'
    printf '1\n'
    printf '%s\n' "${REMNAWAVE_NODE_DOMAIN}"
    printf '%s\n' "${REMNAWAVE_PANEL_IP}"
    printf '%s\n\n' "${node_secret}"
    printf 'y\n'
    printf '2\n'
    printf '%s\n' "${LETSENCRYPT_EMAIL}"
  } | bash ./install_remnawave.sh
}

main() {
  require_root
  require_command git
  require_command perl
  require_command getent

  load_env
  ensure_config
  check_domain_points_to_server "${REMNAWAVE_NODE_DOMAIN}"
  prepare_upstream_repo
  patch_upstream_for_os
  run_installer
}

main "$@"
