#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

IMAGE="${DPICH_IMAGE:-ghcr.io/hyperion-cs/dpich:latest}"
OUT_DIR="${DPICH_OUT_DIR:-${REPO_DIR}/dpich-results}"
MODE="tui"
PULL="always"
TARGET_NAME="Project target"
TARGET_DOMAIN=""
TARGET_IP=""
TARGET_SUBNET=""
TARGET_ASN=""
TARGET_ORG=""
SNI=""
HOST_HEADER=""
FINGERPRINT="chrome"
IFACE="${DPICH_IFACE:-}"
PRINT_CONFIG=0

usage() {
  cat <<'EOF'
Usage:
  tools/dpich/run-dpich.sh [options] [-- extra dpich args]

Modes:
  --tui                 Start dpi-ch TUI (default)
  --all                 Run dpi-ch ALL flow and write reports to ./dpich-results

Target options, pick at most one:
  --target-domain FQDN  Add a project section based on host("FQDN")
  --target-ip IP        Add an exact one-IP section based on subnet("IP/32")
  --target-subnet CIDR  Add a subnet section based on subnet("CIDR")
  --target-asn ASN      Add an ASN section based on as(ASN)
  --target-org TERM     Add an org section based on org("TERM")

Project section modifiers:
  --name TEXT           Target label in dpi-ch
  --sni FQDN            Explicit TLS SNI for IP/subnet/ASN/org targets
  --host FQDN           Explicit HTTP Host header
  --fingerprint VALUE   Siberian checker fingerprint: chrome, firefox, safari,
                        ios, android, edge, 360, qq (default: chrome)
  --iface IFACE_OR_IP   Source interface name or IPv4 for checks

Image/networking:
  --image IMAGE         Docker image (default: ghcr.io/hyperion-cs/dpich:latest)
  --out-dir DIR         Report output directory (default: ./dpich-results)
  --pull always|missing|never
  --print-config        Print generated config.yaml and exit

Examples:
  tools/dpich/run-dpich.sh --target-domain example.com
  tools/dpich/run-dpich.sh --all --target-ip 203.0.113.10 --sni example.com
  tools/dpich/run-dpich.sh --target-asn 29182 --name FirstVDS
EOF
}

fail() {
  printf '[dpich] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

yaml_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "${value}"
}

jsonish_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

target_count() {
  local count=0
  [[ -n "${TARGET_DOMAIN}" ]] && count=$((count + 1))
  [[ -n "${TARGET_IP}" ]] && count=$((count + 1))
  [[ -n "${TARGET_SUBNET}" ]] && count=$((count + 1))
  [[ -n "${TARGET_ASN}" ]] && count=$((count + 1))
  [[ -n "${TARGET_ORG}" ]] && count=$((count + 1))
  printf '%s\n' "${count}"
}

target_filter() {
  if [[ -n "${TARGET_DOMAIN}" ]]; then
    printf 'host(%s)\n' "$(jsonish_string "${TARGET_DOMAIN}")"
  elif [[ -n "${TARGET_IP}" ]]; then
    is_ipv4 "${TARGET_IP}" || fail "--target-ip expects plain IPv4"
    printf 'subnet(%s)\n' "$(jsonish_string "${TARGET_IP}/32")"
  elif [[ -n "${TARGET_SUBNET}" ]]; then
    [[ "${TARGET_SUBNET}" == */* ]] || fail "--target-subnet expects CIDR notation"
    printf 'subnet(%s)\n' "$(jsonish_string "${TARGET_SUBNET}")"
  elif [[ -n "${TARGET_ASN}" ]]; then
    [[ "${TARGET_ASN}" =~ ^[0-9]+$ ]] || fail "--target-asn expects a number"
    printf 'as(%s)\n' "${TARGET_ASN}"
  elif [[ -n "${TARGET_ORG}" ]]; then
    printf 'org(%s)\n' "$(jsonish_string "${TARGET_ORG}")"
  fi
}

write_config() {
  local cfg_file="$1"
  local count filter

  count="$(target_count)"
  [[ "${count}" -le 1 ]] || fail "choose only one target selector"
  filter="$(target_filter)"

  {
    cat <<EOF
updater:
  enabled: false

checkers:
  webhost:
    siberian-conn-count: 4
    siberian-fingerprint: ${FINGERPRINT}
EOF

    if [[ -n "${filter}" ]]; then
      cat <<EOF

    sections:
      - name: $(yaml_quote "Project Reality Targets")
        desc: $(yaml_quote "Targets supplied by tools/dpich/run-dpich.sh")
        targets:
          - name: $(yaml_quote "${TARGET_NAME}")
            filter: $(yaml_quote "${filter}")
            count: 8
            port: 443
EOF

      if [[ -n "${SNI}" ]]; then
        printf '            sni: %s\n' "$(yaml_quote "${SNI}")"
      fi

      if [[ -n "${HOST_HEADER}" ]]; then
        printf '            host: %s\n' "$(yaml_quote "${HOST_HEADER}")"
      fi
    fi

    if [[ -n "${IFACE}" ]]; then
      cat <<EOF

inetutil:
  iface: $(yaml_quote "${IFACE}")
EOF
    fi

    cat <<EOF

all:
  format: json
  checkers:
    - whoami
    - cidrwhitelist
    - webhost
    - dns
  prefix: /results/dpich_
  ts-format: 2006-01-02_15-04
EOF
  } >"${cfg_file}"
}

extra_args=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --tui)
      MODE="tui"
      shift
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --target-domain)
      TARGET_DOMAIN="${2:-}"
      shift 2
      ;;
    --target-ip)
      TARGET_IP="${2:-}"
      shift 2
      ;;
    --target-subnet)
      TARGET_SUBNET="${2:-}"
      shift 2
      ;;
    --target-asn)
      TARGET_ASN="${2:-}"
      shift 2
      ;;
    --target-org)
      TARGET_ORG="${2:-}"
      shift 2
      ;;
    --name)
      TARGET_NAME="${2:-}"
      shift 2
      ;;
    --sni)
      SNI="${2:-}"
      shift 2
      ;;
    --host)
      HOST_HEADER="${2:-}"
      shift 2
      ;;
    --fingerprint)
      FINGERPRINT="${2:-}"
      shift 2
      ;;
    --iface)
      IFACE="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --pull)
      PULL="${2:-}"
      shift 2
      ;;
    --print-config)
      PRINT_CONFIG=1
      shift
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "${FINGERPRINT}" in
  chrome|firefox|safari|ios|android|edge|360|qq) ;;
  *) fail "unsupported fingerprint: ${FINGERPRINT}" ;;
esac

case "${PULL}" in
  always|missing|never) ;;
  *) fail "--pull must be one of: always, missing, never" ;;
esac

if [[ -n "${TARGET_IP}${TARGET_SUBNET}${TARGET_ASN}${TARGET_ORG}" && -z "${SNI}" ]]; then
  printf '[dpich] warning: IP/subnet/ASN/org targets without --sni may not reproduce SNI-bound restrictions\n' >&2
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

cfg_file="${tmp_dir}/config.yaml"
write_config "${cfg_file}"

if [[ "${PRINT_CONFIG}" == "1" ]]; then
  cat "${cfg_file}"
  exit 0
fi

require_command docker
mkdir -p "${OUT_DIR}"

docker_args=(run --rm "--pull=${PULL}" -v "${cfg_file}:/etc/dpich/config.yaml:ro" -v "${OUT_DIR}:/results" "${IMAGE}" --cfg /etc/dpich/config.yaml)
if [[ -t 0 && -t 1 ]]; then
  docker_args=(run --rm -it "--pull=${PULL}" -v "${cfg_file}:/etc/dpich/config.yaml:ro" -v "${OUT_DIR}:/results" "${IMAGE}" --cfg /etc/dpich/config.yaml)
fi

if [[ "${MODE}" == "all" ]]; then
  docker_args+=(--all)
fi

docker_args+=("${extra_args[@]}")

printf '[dpich] image: %s\n' "${IMAGE}"
printf '[dpich] config: %s\n' "${cfg_file}"
printf '[dpich] results: %s\n' "${OUT_DIR}"
exec docker "${docker_args[@]}"
