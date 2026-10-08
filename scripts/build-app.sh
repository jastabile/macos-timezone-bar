#!/bin/bash
# Builds TimeZoneBar.app from the Swift package. Works with Command Line Tools only (no Xcode needed).
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

CONFIG="${1:-release}"
APP="build/TimeZoneBar.app"

swift build -c "$CONFIG" --product TimeZoneBar
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TimeZoneBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TimeZoneBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature so the bundle launches cleanly on Apple silicon.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify "$APP"
echo "Built $APP"
