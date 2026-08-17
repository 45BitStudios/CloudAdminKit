#!/bin/sh
#
# Cuts a release: validates a semver, tags it, and pushes the tag. Pushing
# a "vX.Y.Z" tag is what triggers Xcode Cloud's TestFlight workflow (see
# ci/workflow-testflight.json), whose ci_pre_xcodebuild.sh stamps
# MARKETING_VERSION from the tag. See docs/release-process.md.
#
# Usage: Tools/tag-release.sh 1.2.0

set -e
cd "$(dirname "$0")/.."

VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: Tools/tag-release.sh MAJOR.MINOR.PATCH" >&2
  exit 1
fi

if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: '${VERSION}' is not MAJOR.MINOR.PATCH (e.g. 1.2.0)." >&2
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "error: tag from main, not '${BRANCH}'. Merge first, then re-run from main." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty; commit or stash first." >&2
  exit 1
fi

git fetch origin main --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "error: local main is not up to date with origin/main." >&2
  exit 1
fi

TAG="v${VERSION}"
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag ${TAG} already exists." >&2
  exit 1
fi

git tag -a "$TAG" -m "Release ${VERSION}"
git push origin "$TAG"

echo "Pushed ${TAG}. Xcode Cloud's TestFlight workflow will archive and stamp MARKETING_VERSION=${VERSION}."
