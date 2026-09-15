#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: smoke.sh /private/backup-dir/users.count" >&2; exit 2; }
expected_users="$(cat "$1")"
[[ "$expected_users" =~ ^[0-9]+$ ]] || { echo "invalid users.count" >&2; exit 2; }
compose=/opt/remnawave/docker-compose.yml
for name in remnanode remnawave-subscription-page remnawave remnawave-redis remnawave-db remnawave-nginx; do
  [[ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ]] || {
    echo "$name is not running" >&2; exit 1
  }
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' remnawave)" == healthy ]]
[[ "$(docker inspect -f '{{.State.Health.Status}}' remnawave-db)" == healthy ]]
[[ "$(docker inspect -f '{{.State.Health.Status}}' remnawave-redis)" == healthy ]]
actual_users="$(docker exec remnawave-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from users"')"
[[ "$actual_users" == "$expected_users" ]] || {
  echo "users count mismatch: expected=$expected_users actual=$actual_users" >&2; exit 1
}
docker compose -f "$compose" config --quiet
curl -fsS --max-time 10 http://127.0.0.1:3001/health >/dev/null
curl -fsS --max-time 10 --resolve panel.silnetbridge.com:443:127.0.0.1 \
  https://panel.silnetbridge.com/ >/dev/null
printf 'local restore smoke passed; users=%s\n' "$actual_users"
