#!/bin/sh
#
# Renders named SwiftUI screens in {{UI_MODULE}} to PNG.
# Output: Designs/previews/<device>/<Screen>-{light,dark}.png
#   device = iphone | ipad | mac | tv | vision | watch
#
# Usage:  Tools/capture-previews.sh [output-dir] [devices]
#   devices defaults to all: iphone,ipad,mac,tv,vision,watch

set -e
cd "$(dirname "$0")/.."

# Scheme post-actions inherit xcodebuild's env. That leaks:
#   SDKROOT=auto                              → SDK "auto" cannot be located
#   OTHER_SWIFT_FLAGS without -package-name   → `package` access fails
#   BUILD_DIR / OBJROOT / SWIFT_INCLUDE_PATHS → SPM cannot find products
# Run `swift` in a login-like env. Unsetting SDKROOT alone is not enough.
developer_dir=""
if [ -n "${DEVELOPER_DIR-}" ]; then
    case "$DEVELOPER_DIR" in
        /*) developer_dir="$DEVELOPER_DIR" ;;
    esac
fi

run_swift() {
    extra=""
    [ -n "$developer_dir" ] && extra="$extra DEVELOPER_DIR=$developer_dir"
    [ -n "${SSH_AUTH_SOCK-}" ] && extra="$extra SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    [ -n "${__CF_USER_TEXT_ENCODING-}" ] && extra="$extra __CF_USER_TEXT_ENCODING=$__CF_USER_TEXT_ENCODING"
    # shellcheck disable=SC2086
    env -i \
        HOME="$HOME" \
        USER="${USER-}" \
        LOGNAME="${LOGNAME-${USER-}}" \
        PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" \
        SHELL="${SHELL:-/bin/sh}" \
        TMPDIR="${TMPDIR:-/tmp}" \
        LANG="${LANG:-en_US.UTF-8}" \
        TERM="${TERM:-dumb}" \
        $extra \
        /usr/bin/xcrun --sdk macosx swift "$@"
}

out="${1:-Designs/previews}"
devices="${2:-}"
mkdir -p "$out"

echo "Capturing {{APP_NAME}} preview screens into $out"
if [ -n "$devices" ]; then
    run_swift run --package-path . preview-capture --output "$out" --devices "$devices"
else
    run_swift run --package-path . preview-capture --output "$out"
fi
echo "capture-previews: done"
