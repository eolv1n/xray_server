#!/usr/bin/env bash
set -euo pipefail

# Run on the source VPS only during an authorized backup window. Output is secret.
[[ "$EUID" -eq 0 ]] || { echo "root required" >&2; exit 2; }
[[ $# -eq 1 ]] || { echo "usage: backup.sh /private/backup-dir" >&2; exit 2; }
backup_dir="$1"
[[ ! -e "$backup_dir" ]] || { echo "backup destination already exists" >&2; exit 2; }
umask 077
mkdir -m 0700 "$backup_dir"
trap 'rm -rf "$backup_dir"' ERR

docker inspect -f '{{.State.Running}}' remnawave-db | grep -qx true
docker exec remnawave-db sh -lc 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' >"$backup_dir/postgres.dump"
docker exec remnawave-db sh -lc 'pg_dumpall --globals-only -U "$POSTGRES_USER"' >"$backup_dir/postgres-globals.sql"
docker exec remnawave-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from users"' >"$backup_dir/users.count"

tar -C / -cf "$backup_dir/private-state.tar" \
  opt/remnawave/.env opt/remnawave/docker-compose.yml opt/remnawave/nginx.conf \
  etc/letsencrypt home/eol/.ssh/authorized_keys home/eol/.local/bin home/eol/.config
sha256sum "$backup_dir/postgres.dump" "$backup_dir/postgres-globals.sql" \
  "$backup_dir/users.count" "$backup_dir/private-state.tar" >"$backup_dir/SHA256SUMS"
chmod 0600 "$backup_dir"/*
trap - ERR
printf 'Backup ready at %s; transfer it only to protected storage outside Git.\n' "$backup_dir"
