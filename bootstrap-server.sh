#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER="eol"
DEFAULT_OPEN_PORTS="22 80 443"
DEFAULT_FAIL2BAN_IGNORE_IPS="127.0.0.1/8 ::1"

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

append_authorized_key() {
  local user_name="$1"
  local public_key="$2"
  local ssh_dir="/home/${user_name}/.ssh"
  local auth_file="${ssh_dir}/authorized_keys"

  install -d -m 0700 -o "${user_name}" -g "${user_name}" "${ssh_dir}"
  touch "${auth_file}"
  chown "${user_name}:${user_name}" "${auth_file}"
  chmod 0600 "${auth_file}"

  if ! grep -qxF "${public_key}" "${auth_file}"; then
    printf '%s\n' "${public_key}" >>"${auth_file}"
  fi
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

write_fail2ban_jail() {
  cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
banaction = ufw
ignoreip = ${FAIL2BAN_IGNORE_IPS}

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
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

  if [[ -n "${ADMIN_PUBKEY}" ]]; then
    append_authorized_key "${ADMIN_USER}" "${ADMIN_PUBKEY}"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt upgrade -y
  apt install -y \
    ca-certificates \
    curl \
    git \
    docker.io \
    docker-compose-v2 \
    ufw \
    fail2ban \
    iperf3 \
    vnstat \
    iftop \
    nload \
    bmon \
    conntrack \
    net-tools
}

configure_docker() {
  getent group docker >/dev/null 2>&1 || groupadd docker
  usermod -aG docker "${ADMIN_USER}"
  systemctl enable --now docker
}

configure_fail2ban() {
  mkdir -p /etc/fail2ban
  write_fail2ban_jail
  systemctl enable --now fail2ban
}

configure_kernel() {
  cat >/etc/modules-load.d/xray-network-tuning.conf <<'EOF'
tcp_bbr
EOF

  cat >/etc/sysctl.d/99-xray-network-tuning.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
vm.overcommit_memory = 1
EOF

  modprobe tcp_bbr 2>/dev/null || true
  sysctl --system >/dev/null

  if command -v tc >/dev/null 2>&1 && ip link show eth0 >/dev/null 2>&1; then
    tc qdisc replace dev eth0 root fq 2>/dev/null || true
  fi
}

configure_network_tooling() {
  if systemctl list-unit-files vnstat.service >/dev/null 2>&1; then
    systemctl enable --now vnstat
  fi
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
  1. Verify SSH login as ${ADMIN_USER}
  2. Add any extra SSH public keys to /home/${ADMIN_USER}/.ssh/authorized_keys
  3. Optionally disable PasswordAuthentication after key login works everywhere
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
  ADMIN_PUBKEY="$(prompt_text "Optional SSH public key for ${ADMIN_USER}" "" 0)"
  OPEN_PORTS="$(prompt_text "TCP ports to allow through UFW" "${DEFAULT_OPEN_PORTS}" 1)"
  FAIL2BAN_IGNORE_IPS="$(prompt_text "Fail2ban ignore IPs/networks" "${DEFAULT_FAIL2BAN_IGNORE_IPS}" 1)"

  create_admin_user
  install_packages
  configure_docker
  configure_fail2ban
  configure_kernel
  configure_network_tooling
  configure_ssh
  configure_firewall
  print_summary
}

main "$@"
