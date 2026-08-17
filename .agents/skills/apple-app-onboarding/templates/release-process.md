# Release process: tagging, versioning, build numbers

## Scheme

`MARKETING_VERSION` follows semver (`MAJOR.MINOR.PATCH`, e.g. `1.2.0`) —
major for breaking/architecture changes, minor for new content or features,
patch for fixes.

`CURRENT_PROJECT_VERSION` (the build number) is managed by Xcode Cloud, not
by hand — see one-time setup below.

## One-time setup (App Store Connect, not repo-controlled)

In App Store Connect → Xcode Cloud → the `TestFlight` workflow → Start
Conditions/Versioning, enable **"Xcode Cloud automatically manages build
number"**. That keeps `CURRENT_PROJECT_VERSION` monotonically increasing
across archive builds without any script maintaining it. This can't be set
from the repo — the workflow files in `ci/` are reference exports, not the
live config — so it's a manual toggle done once in the ASC UI.

## Cutting a release

1. Merge everything for the release into `main`.
2. From `main`, run `Tools/tag-release.sh 1.2.0`. It validates the version,
   tags `v1.2.0`, and pushes the tag.
3. Pushing a `v*` tag triggers the `TestFlight` Xcode Cloud workflow
   (`ci/workflow-testflight.json`), which:
   - runs `ci_scripts/ci_pre_xcodebuild.sh`, which reads `CI_TAG` and stamps
     `MARKETING_VERSION` (across all targets in `{{APP_NAME}}.xcodeproj`) to
     match the tag,
   - archives every shipping platform with the build number Xcode Cloud
     assigned,
   - uploads to TestFlight (internal).

No manual edits to `project.pbxproj` version fields are needed for a
release — the tag is the single source of truth for `MARKETING_VERSION`.
