#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'EOF'
[configure] Legacy configure flow was removed.
[configure] Use the unified installer menu instead:
  sudo bash ./install-remnawave.sh
EOF

exec bash "${REPO_DIR}/install-remnawave.sh"
