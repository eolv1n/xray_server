#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER="eol"
DEFAULT_OPEN_PORTS="22 80 443"

log() {
  printf '[bootstrap] %s\n' "$*"
}

fail() {
  printf '[bootstrap] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "run this script as root"
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

prompt_secret() {
  local label="$1"
  local value

  while true; do
    read -r -s -p "${label}: " value
    printf '\n'
    value="$(trim "${value}")"
    if [[ -z "${value}" ]]; then
      log "value is required"
      continue
    fi
    printf '%s' "${value}"
    return
  done
}

write_sshd_hardening() {
  cat >/etc/ssh/sshd_config.d/60-bootstrap-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers ${ADMIN_USER}
EOF
}

create_admin_user() {
  if id -u "${ADMIN_USER}" >/dev/null 2>&1; then
    log "user ${ADMIN_USER} already exists"
  else
    adduser --disabled-password --gecos "" "${ADMIN_USER}"
  fi

  printf '%s:%s\n' "${ADMIN_USER}" "${ADMIN_PASS}" | chpasswd
  usermod -aG sudo "${ADMIN_USER}"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt upgrade -y
  apt install -y ca-certificates curl git docker.io docker-compose-v2 ufw fail2ban
}

configure_docker() {
  getent group docker >/dev/null 2>&1 || groupadd docker
  usermod -aG docker "${ADMIN_USER}"
  systemctl enable --now docker
}

configure_fail2ban() {
  systemctl enable --now fail2ban
}

configure_ssh() {
  mkdir -p /etc/ssh/sshd_config.d
  write_sshd_hardening
  sshd -t
  systemctl restart ssh
}

configure_firewall() {
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  for port in ${OPEN_PORTS}; do
    ufw allow "${port}"/tcp
  done

  ufw --force enable
}

print_summary() {
  cat <<EOF

[bootstrap] completed

Admin user:
  ${ADMIN_USER}

Open TCP ports:
  ${OPEN_PORTS}

Current SSH policy:
  - root password login disabled
  - password login kept enabled for ${ADMIN_USER}
  - key login enabled

Recommended next steps:
  1. Add your SSH public key to /home/${ADMIN_USER}/.ssh/authorized_keys
  2. Verify SSH login as ${ADMIN_USER}
  3. Optionally disable PasswordAuthentication after key login works
  4. Reboot if apt upgraded the kernel
EOF
}

main() {
  require_root
  require_tty

  cat <<'EOF'
This bootstrap prepares a clean Ubuntu VPS before cloning the repo.
It updates the system, installs Docker/Git/Curl/UFW/Fail2Ban, creates a sudo user,
disables root SSH login, and opens only the ports you choose.

Password SSH stays enabled for the new admin user on purpose, so you do not lose access
before adding your SSH key.
EOF

  ADMIN_USER="$(prompt_text "Admin username" "${DEFAULT_USER}" 1)"
  ADMIN_PASS="$(prompt_secret "Password for ${ADMIN_USER}")"
  OPEN_PORTS="$(prompt_text "TCP ports to allow through UFW" "${DEFAULT_OPEN_PORTS}" 1)"

  create_admin_user
  install_packages
  configure_docker
  configure_fail2ban
  configure_ssh
  configure_firewall
  print_summary
}

main "$@"
