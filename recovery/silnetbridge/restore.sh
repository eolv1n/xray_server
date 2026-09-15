#!/usr/bin/env bash
set -euo pipefail

# New VPS only. Keep old DNS and old VPS untouched until smoke passes.
[[ "$EUID" -eq 0 ]] || { echo "root required" >&2; exit 2; }
[[ $# -eq 1 ]] || { echo "usage: restore.sh /private/backup-dir" >&2; exit 2; }
[[ "${SILNET_NEW_VPS_RECOVERY:-}" == "new-vps-only" ]] || {
  echo "set SILNET_NEW_VPS_RECOVERY=new-vps-only on the replacement VPS" >&2
  exit 2
}
[[ ! -e /opt/remnawave/docker-compose.yml ]] || {
  echo "refusing to overwrite an existing Remnawave deployment" >&2
  exit 2
}
backup_dir="$1"
recovery_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
(cd "$backup_dir" && sha256sum -c SHA256SUMS)
test -s "$backup_dir/postgres.dump"
test -s "$backup_dir/users.count"

umask 077
tar -C / -xf "$backup_dir/private-state.tar"
python3 "$recovery_dir/pin-images.py" /opt/remnawave/docker-compose.yml
docker compose -f /opt/remnawave/docker-compose.yml config --quiet
docker compose -f /opt/remnawave/docker-compose.yml pull
docker compose -f /opt/remnawave/docker-compose.yml up -d remnawave-db remnawave-redis

for attempt in {1..30}; do
  if docker exec remnawave-db sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null; then
    break
  fi
  sleep 2
done
docker exec remnawave-db sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null
docker exec -i remnawave-db sh -lc 'pg_restore --clean --if-exists --no-owner -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  <"$backup_dir/postgres.dump"
docker compose -f /opt/remnawave/docker-compose.yml up -d
"$recovery_dir/smoke.sh" "$backup_dir/users.count"
