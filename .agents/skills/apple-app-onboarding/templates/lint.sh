#!/bin/sh
#
# Runs the exact lint + format checks CI gates on (ci_scripts/ci_post_clone.sh).
# Green here means the lint half of the cloud build is green.
#
# Usage:  Tools/lint.sh          # check only
#         Tools/lint.sh --fix    # apply SwiftFormat + SwiftLint autocorrections first

set -e
cd "$(dirname "$0")/.."

for tool in swiftlint swiftformat; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not installed — brew install $tool" >&2
    exit 1
  fi
done

if [ "$1" = "--fix" ]; then
  swiftformat .
  swiftlint --fix --quiet
fi

swiftformat --lint .
swiftlint --strict --quiet
echo "lint: clean."
