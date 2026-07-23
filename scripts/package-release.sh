#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/build/Claude Quota Island.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/config/Info.plist")"
RELEASE_DIR="$PROJECT_ROOT/dist"
ARCHIVE="$RELEASE_DIR/Claude-Quota-Island-$VERSION.zip"
CHECKSUM="$ARCHIVE.sha256"

if [[ ! "$VERSION" =~ '^[0-9]+([.][0-9]+){2}([.-][A-Za-z0-9]+)*$' ]]; then
  echo "Refusing invalid release version: $VERSION" >&2
  exit 2
fi

"$PROJECT_ROOT/scripts/build-app.sh"
mkdir -p "$RELEASE_DIR"
rm -f "$ARCHIVE" "$CHECKSUM"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo "$ARCHIVE"
echo "$CHECKSUM"
