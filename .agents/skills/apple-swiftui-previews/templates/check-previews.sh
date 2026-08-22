#!/bin/sh
#
# Every file-scope SwiftUI View in {{UI_SOURCE_PATHS}} needs a #Preview or
# PreviewProvider with mock data. Nested `private struct` rows are covered by
# the parent file's preview.
#
# Usage:  Tools/check-previews.sh
# Exit 1 when a View file has no preview.

set -e
cd "$(dirname "$0")/.."

missing=0
for f in $(find {{UI_SOURCE_PATHS}} -name '*.swift' ! -path '*/.docc/*' | sort); do
    if grep -Eq '^(public )?struct [A-Za-z0-9_]+[[:space:]]*:[[:space:]]*View' "$f"; then
        if ! grep -Eq '#Preview|PreviewProvider' "$f"; then
            echo "FAIL: $f has a file-scope View but no #Preview"
            missing=1
        fi
    fi
done

if [ "$missing" -eq 0 ]; then
    echo "check-previews: every file-scope View has a Swift preview."
    exit 0
fi
exit 1
