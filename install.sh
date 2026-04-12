#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'EOF'
[install] Legacy install flow was removed.
[install] Use the unified installer menu:
  sudo bash ./install-remnawave.sh
EOF

exec bash "${REPO_DIR}/install-remnawave.sh"
