#!/bin/sh
#
# Xcode Cloud pre-xcodebuild step: stamp MARKETING_VERSION from the release
# tag before the Archive actions run.
#
# Only the TestFlight workflow (tagStartCondition on "v*", see
# ci/workflow-testflight.json) sets CI_TAG, so this is a no-op on the CI
# workflow's plain branch/PR builds.
#
# Build numbers are NOT handled here: CURRENT_PROJECT_VERSION is synced by
# Xcode Cloud's own "automatically manage build number" workflow setting
# (App Store Connect > Xcode Cloud > workflow > Start Conditions), which
# increments per archive build. See docs/release-process.md.

set -e

if [ -z "${CI_TAG:-}" ]; then
  echo "No CI_TAG set; skipping marketing version stamping."
  exit 0
fi

VERSION=$(echo "$CI_TAG" | sed -E 's/^v//')

if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: CI_TAG '${CI_TAG}' does not match vMAJOR.MINOR.PATCH; refusing to stamp a version." >&2
  exit 1
fi

PBXPROJ="${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE/repository}/{{APP_NAME}}/{{APP_NAME}}.xcodeproj/project.pbxproj"

echo "Stamping MARKETING_VERSION = ${VERSION} (from tag ${CI_TAG}) into $PBXPROJ"
sed -i '' -E "s/MARKETING_VERSION = [0-9]+\.[0-9]+(\.[0-9]+)?;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
