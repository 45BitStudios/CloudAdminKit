#!/bin/sh
#
# Lists public types and functions in Sources/ that have no `///` doc
# comment. Stored properties and memberwise inits are deliberately NOT
# checked — many are self-evident, and mandating docs there breeds filler.
# Toolchain-free (awk only), so it runs anywhere — including cloud agent
# sessions and CI. Exit status 1 when anything is undocumented, so it can
# gate a hook or CI step if desired.
#
# Usage:  Tools/check-docs.sh [path ...]     (defaults to Sources)

set -e
cd "$(dirname "$0")/.."

paths="${*:-Sources}"
found=0

for f in $(find $paths -name '*.swift' ! -path '*/.docc/*'); do
    result=$(awk '
        # Track whether the nearest preceding non-attribute, non-directive
        # line was a doc comment.
        /^[[:space:]]*\/\/\// { doc = 1; next }
        # Attributes, availability, and conditional-compilation lines sit
        # between a doc comment and its declaration — skip without resetting.
        /^[[:space:]]*@/ || /^[[:space:]]*#(if|else|elseif|endif)/ { next }
        /^[[:space:]]*$/ { next }
        {
            if ($0 ~ /(^|[[:space:]])public[[:space:]](final[[:space:]]|static[[:space:]]|nonisolated[[:space:]])*(struct|class|actor|enum|protocol|func|typealias|subscript)([[:space:]]|\()/ && doc == 0)
                printf "%s:%d: %s\n", FILENAME, NR, $0
            doc = 0
        }
    ' "$f")
    if [ -n "$result" ]; then
        echo "$result"
        found=1
    fi
done

if [ "$found" -eq 0 ]; then
    echo "check-docs: every public declaration is documented."
fi
exit $found
