#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLED_APP="$HOME/Applications/Claude Quota Island.app"
INSTALLED_EXECUTABLE="$INSTALLED_APP/Contents/MacOS/ClaudeQuotaIslandApp"

CQI_APP_OUTPUT="$INSTALLED_APP" "$PROJECT_ROOT/scripts/build-app.sh"

existing_pids=("${(@f)$(pgrep -f -x "$INSTALLED_EXECUTABLE" || true)}")
for pid in "${existing_pids[@]}"; do
  if [[ -n "$pid" ]]; then
    kill "$pid"
  fi
done

for pid in "${existing_pids[@]}"; do
  if [[ -n "$pid" ]]; then
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
  fi
done

open -na "$INSTALLED_APP"

echo "Installed and launched: $INSTALLED_APP"
