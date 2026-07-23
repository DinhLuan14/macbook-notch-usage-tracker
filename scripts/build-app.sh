#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_OUTPUT="$PROJECT_ROOT/build/Claude Quota Island.app"
OUTPUT_PATH="${CQI_APP_OUTPUT:-$DEFAULT_OUTPUT}"
OUTPUT_PATH="${OUTPUT_PATH:A}"
OUTPUT_DIRECTORY="${OUTPUT_PATH:h}"
OUTPUT_NAME="${OUTPUT_PATH:t}"

case "$OUTPUT_DIRECTORY" in
  "$PROJECT_ROOT/build"|"$HOME/Applications")
    ;;
  *)
    echo "Refusing unexpected app output path: $OUTPUT_PATH" >&2
    exit 2
    ;;
esac

case "$OUTPUT_NAME" in
  "Claude Quota Island.app"|"Claude Quota Island Dev.app")
    ;;
  *)
    echo "Refusing unexpected app bundle name: $OUTPUT_NAME" >&2
    exit 2
    ;;
esac

swift build --package-path "$PROJECT_ROOT" -c release --product ClaudeQuotaIslandApp
BIN_DIRECTORY="$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)"
STAGING_DIRECTORY="$(mktemp -d)"
STAGING_APP="$STAGING_DIRECTORY/Claude Quota Island.app"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

mkdir -p "$STAGING_APP/Contents/MacOS"
cp "$BIN_DIRECTORY/ClaudeQuotaIslandApp" "$STAGING_APP/Contents/MacOS/ClaudeQuotaIslandApp"
cp "$PROJECT_ROOT/config/Info.plist" "$STAGING_APP/Contents/Info.plist"

SIGNING_IDENTITY="${CQI_CODE_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" \
  --entitlements "$PROJECT_ROOT/config/ClaudeQuotaIslandApp.entitlements" \
  "$STAGING_APP"

mkdir -p "$(dirname "$OUTPUT_PATH")"
if [ -e "$OUTPUT_PATH" ]; then
  rm -rf "$OUTPUT_PATH"
fi
mv "$STAGING_APP" "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
