# Sourced by build-app.sh / test.sh. Picks a working SDK and toolchain flags.

TOOLCHAIN_BIN="$(dirname "$(xcrun --find swift)")"
PLUGIN_DIR="$TOOLCHAIN_BIN/../lib/swift/host/plugins"

# Some Command Line Tools releases ship a macOS SDK whose SwiftUI declares @State etc. as
# macros implemented by a `SwiftUIMacros` plugin that the same CLT does not include
# ("plugin for module 'SwiftUIMacros' not found"). In that case fall back to the newest
# installed SDK that predates it. Set SDKROOT yourself to override.
needs_state_macro() {
    grep -qs 'type: "StateMacro"' "$1"/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/*.swiftinterface
}

if [ -z "${SDKROOT:-}" ] && [ ! -e "$PLUGIN_DIR/libSwiftUIMacros.dylib" ]; then
    SDK="$(xcrun --show-sdk-path)"
    if needs_state_macro "$SDK"; then
        SDK_DIR="$(dirname "$SDK")"
        for candidate in $(ls -d "$SDK_DIR"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
            if ! needs_state_macro "$candidate"; then
                export SDKROOT="$candidate"
                echo "note: using $SDKROOT (default SDK needs a SwiftUIMacros plugin this toolchain lacks)" >&2
                break
            fi
        done
    fi
fi
