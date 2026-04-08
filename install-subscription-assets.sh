#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
EXAMPLE_ENV_FILE="${REPO_DIR}/.env.example"

log() {
  printf '[subscription-assets] %s\n' "$*"
}

fail() {
  printf '[subscription-assets] error: %s\n' "$*" >&2
  exit 1
}

require_tty() {
  [[ -t 0 ]] || fail "interactive terminal is required"
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  elif [[ -f "${EXAMPLE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${EXAMPLE_ENV_FILE}"
  fi

  APP_DIR="${APP_DIR:-/opt/silentbridge}"
  PANEL_DOMAIN="${PANEL_DOMAIN:-}"
  SUB_SUPPORT_URL="${SUB_SUPPORT_URL:-}"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
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

select_page_template() {
  local choice

  while true; do
    cat <<'EOF'
Choose subscription page template:
  1) Local polished template from this repository
  2) Orion by legiz
  3) streletskiy marzban-sub-page
  4) Custom HTTPS URL
EOF
    read -r -p "Enter choice [1-4]: " choice
    case "${choice}" in
      1)
        PAGE_TEMPLATE_MODE="local"
        PAGE_TEMPLATE_URL=""
        return
        ;;
      2)
        PAGE_TEMPLATE_MODE="remote"
        PAGE_TEMPLATE_URL="https://raw.githubusercontent.com/legiz-ru/Orion/main/marzban/index.html"
        return
        ;;
      3)
        PAGE_TEMPLATE_MODE="remote"
        PAGE_TEMPLATE_URL="https://raw.githubusercontent.com/streletskiy/marzban-sub-page/main/index.html"
        return
        ;;
      4)
        PAGE_TEMPLATE_MODE="remote"
        PAGE_TEMPLATE_URL="$(prompt_text "Custom subscription page URL" "${PAGE_TEMPLATE_URL:-}" 1)"
        return
        ;;
      *)
        log "invalid choice"
        ;;
    esac
  done
}

select_v2ray_template() {
  local choice

  while true; do
    cat <<'EOF'
Choose V2Ray subscription template:
  1) Skip
  2) xray client template by legiz
  3) RU bundle by legiz
  4) Custom HTTPS URL
EOF
    read -r -p "Enter choice [1-4]: " choice
    case "${choice}" in
      1) V2RAY_URL="" ; return ;;
      2) V2RAY_URL="https://raw.githubusercontent.com/cortez24rus/marz-sub/main/v2ray/default.json" ; return ;;
      3) V2RAY_URL="https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/other/marzban-v2ray-ru-bundle.json" ; return ;;
      4) V2RAY_URL="$(prompt_text "Custom V2Ray template URL" "${V2RAY_URL:-}" 1)" ; return ;;
      *) log "invalid choice" ;;
    esac
  done
}

select_clash_template() {
  local choice

  while true; do
    cat <<'EOF'
Choose Clash/Mihomo subscription template:
  1) Skip
  2) RU bundle by legiz
  3) Skrepysh template
  4) Re-filter template
  5) Custom HTTPS URL
EOF
    read -r -p "Enter choice [1-5]: " choice
    case "${choice}" in
      1) CLASH_URL="" ; return ;;
      2) CLASH_URL="https://raw.githubusercontent.com/cortez24rus/marz-sub/main/clash/default.yml" ; return ;;
      3) CLASH_URL="https://raw.githubusercontent.com/Skrepysh/tools/main/marzban-subscription-templates/clash-sub.yml" ; return ;;
      4) CLASH_URL="https://raw.githubusercontent.com/cortez24rus/marz-sub/main/clash/refilter.yml" ; return ;;
      5) CLASH_URL="$(prompt_text "Custom Clash template URL" "${CLASH_URL:-}" 1)" ; return ;;
      *) log "invalid choice" ;;
    esac
  done
}

select_singbox_template() {
  local choice

  while true; do
    cat <<'EOF'
Choose sing-box subscription template:
  1) Skip
  2) Secret-Sing-Box by BLUEBL0B
  3) Skrepysh template
  4) Re-filter template
  5) Custom HTTPS URL
EOF
    read -r -p "Enter choice [1-5]: " choice
    case "${choice}" in
      1) SINGBOX_URL="" ; return ;;
      2) SINGBOX_URL="https://raw.githubusercontent.com/cortez24rus/marz-sub/main/singbox/ssb.json" ; return ;;
      3) SINGBOX_URL="https://raw.githubusercontent.com/Skrepysh/tools/main/marzban-subscription-templates/sing-sub.json" ; return ;;
      4) SINGBOX_URL="https://raw.githubusercontent.com/cortez24rus/marz-sub/main/singbox/refilter.json" ; return ;;
      5) SINGBOX_URL="$(prompt_text "Custom sing-box template URL" "${SINGBOX_URL:-}" 1)" ; return ;;
      *) log "invalid choice" ;;
    esac
  done
}

ensure_dirs() {
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates/subscription"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates/v2ray"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates/clash"
  install -d -m 0755 "${APP_DIR}/marzban_lib/templates/singbox"
}

download_file() {
  local url="$1"
  local target="$2"
  curl -fsSL "${url}" -o "${target}"
}

apply_page_template() {
  local target="${APP_DIR}/marzban_lib/templates/subscription/index.html"

  if [[ "${PAGE_TEMPLATE_MODE}" == "local" ]]; then
    install -m 0644 "${REPO_DIR}/templates/subscription-index.html.tpl" "${target}"
  else
    download_file "${PAGE_TEMPLATE_URL}" "${target}"
  fi

  if [[ -n "${SUB_SUPPORT_URL}" ]]; then
    sed -i "s|https://t.me/yourID|${SUB_SUPPORT_URL}|g" "${target}" || true
    sed -i "s|https://t.me/legiz_trashbag|${SUB_SUPPORT_URL}|g" "${target}" || true
    sed -i "s|https://t.me/gozargah_marzban|${SUB_SUPPORT_URL}|g" "${target}" || true
    sed -i "s|https://github.com/Gozargah/Marzban#donation|${SUB_SUPPORT_URL}|g" "${target}" || true
  fi
}

update_or_add_env() {
  local key="$1"
  local value="$2"
  local file="$3"

  awk -v key="${key}" -v value="${value}" '
    $1 != key && !(NF > 1 && $1 == "#" && $2 == key) {print}
    END {print key "=" value}
  ' "${file}" > "${file}.tmp"

  mv "${file}.tmp" "${file}"
}

main() {
  require_tty
  load_env

  [[ -d "${APP_DIR}" ]] || fail "APP_DIR does not exist yet: ${APP_DIR}"
  [[ -f "${APP_DIR}/marzban/.env" ]] || fail "Marzban env file not found: ${APP_DIR}/marzban/.env"

  SUB_SUPPORT_URL="$(prompt_text "Support URL for subscription page (Telegram or site)" "${SUB_SUPPORT_URL}" 0)"

  select_page_template
  select_v2ray_template
  select_clash_template
  select_singbox_template

  ensure_dirs
  apply_page_template

  if [[ -n "${V2RAY_URL}" ]]; then
    download_file "${V2RAY_URL}" "${APP_DIR}/marzban_lib/templates/v2ray/default.json"
    update_or_add_env "V2RAY_SUBSCRIPTION_TEMPLATE" "\"v2ray/default.json\"" "${APP_DIR}/marzban/.env"
  fi

  if [[ -n "${CLASH_URL}" ]]; then
    download_file "${CLASH_URL}" "${APP_DIR}/marzban_lib/templates/clash/default.yml"
    download_file "https://raw.githubusercontent.com/cortez24rus/marz-sub/main/clash/settings.yml" "${APP_DIR}/marzban_lib/templates/clash/settings.yml"
    update_or_add_env "CLASH_SUBSCRIPTION_TEMPLATE" "\"clash/default.yml\"" "${APP_DIR}/marzban/.env"
    update_or_add_env "CLASH_SETTINGS_TEMPLATE" "\"clash/settings.yml\"" "${APP_DIR}/marzban/.env"
  fi

  if [[ -n "${SINGBOX_URL}" ]]; then
    download_file "${SINGBOX_URL}" "${APP_DIR}/marzban_lib/templates/singbox/default.json"
    update_or_add_env "SINGBOX_SUBSCRIPTION_TEMPLATE" "\"singbox/default.json\"" "${APP_DIR}/marzban/.env"
  fi

  update_or_add_env "CUSTOM_TEMPLATES_DIRECTORY" "\"/var/lib/marzban/templates/\"" "${APP_DIR}/marzban/.env"
  update_or_add_env "SUBSCRIPTION_PAGE_TEMPLATE" "\"subscription/index.html\"" "${APP_DIR}/marzban/.env"

  if [[ -n "${SUB_SUPPORT_URL}" ]]; then
    update_or_add_env "SUB_SUPPORT_URL" "\"${SUB_SUPPORT_URL}\"" "${APP_DIR}/marzban/.env"
  fi

  cat <<EOF

Subscription assets installed.

Runtime directory:
  ${APP_DIR}

Updated files:
  ${APP_DIR}/marzban/.env
  ${APP_DIR}/marzban_lib/templates/subscription/index.html

Next step:
  docker compose -f ${APP_DIR}/docker-compose.yml restart marzban angie
EOF
}

main "$@"
