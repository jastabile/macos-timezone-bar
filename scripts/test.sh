#!/bin/bash
# Runs the unit tests (Swift Testing). Works with Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

# Workaround: with Command Line Tools, SwiftPM intermittently omits the swift-testing macro
# plugin directory from clean builds ("plugin for module 'TestingMacros' not found").
# Passing it explicitly makes the build deterministic.
PLUGINS="$PLUGIN_DIR/testing"
EXTRA=()
if [ -d "$PLUGINS" ]; then EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS"); fi

swift test "${EXTRA[@]}" "$@"
