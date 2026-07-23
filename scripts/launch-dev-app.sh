#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_APP="$HOME/Applications/Claude Quota Island Dev.app"

CQI_APP_OUTPUT="$DEV_APP" "$PROJECT_ROOT/scripts/build-app.sh"
open -na "$DEV_APP"
