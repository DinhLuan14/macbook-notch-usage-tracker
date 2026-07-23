#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLED_APP="$HOME/Applications/Claude Quota Island.app"

CQI_APP_OUTPUT="$INSTALLED_APP" "$PROJECT_ROOT/scripts/build-app.sh"
open -na "$INSTALLED_APP"

echo "Installed and launched: $INSTALLED_APP"
