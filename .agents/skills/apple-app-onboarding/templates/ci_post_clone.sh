#!/bin/sh
#
# Xcode Cloud post-clone gate: lint + format + package tests. A non-zero exit
# here fails the build, so this is what gates every PR.
#
# Tests run with `swift test` (not a native Xcode test action) because the app
# project references {{APP_NAME}}Kit as a local SwiftPM package, and a package
# test scheme can't share the app's .xcodeproj container in a single Xcode
# Cloud workflow (docs/apple-multiplatform-ci-gotchas.md §4).
#
# Runs before the Build/Archive action. See ci/workflow-ci.json.

set -e

# Xcode Cloud checks the primary repo out at CI_PRIMARY_REPOSITORY_PATH; the
# Package.swift lives at the repo root.
cd "${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE/repository}"

echo "Installing lint tools"
brew install swiftlint swiftformat

echo "Linting (same checks as Tools/lint.sh)"
swiftformat --lint .
swiftlint --strict --quiet

echo "Checking binary-size budgets (Tools/check-size.sh)"
Tools/check-size.sh

echo "Running {{APP_NAME}}Kit tests via swift test in $(pwd)"
swift test
