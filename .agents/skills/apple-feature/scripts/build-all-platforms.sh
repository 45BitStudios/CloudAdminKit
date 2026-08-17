#!/bin/sh
# Hard compile gate for a studio Apple app repo.
# Discover scheme + shipping platforms from ci/workflow-ci.json (what Xcode Cloud
# actually builds), else Package.swift, then run the repo's Tools scripts, swift
# test, and one generic-destination xcodebuild per platform.
#
# Usage:
#   build-all-platforms.sh [--discover] [--skip-tools] [--repo <path>]
# Exit 1 on any FAIL. --discover prints the matrix and exits 0 without building.
set -eu

discover_only=0
skip_tools=0
repo=$(pwd)

while [ $# -gt 0 ]; do
  case $1 in
    --discover) discover_only=1; shift ;;
    --skip-tools) skip_tools=1; shift ;;
    --repo) repo=$2; shift 2 ;;
    -h|--help)
      echo "usage: build-all-platforms.sh [--discover] [--skip-tools] [--repo <path>]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

cd "$repo"
repo=$(pwd)
status=0
fail() { echo "FAIL: $1"; status=1; }
pass() { echo "PASS: $1"; }
skip() { echo "SKIP: $1"; }

# --- discover project / scheme / platforms --------------------------------

ci="$repo/ci/workflow-ci.json"
project=""
scheme=""
platforms=""

if [ -f "$ci" ]; then
  project=$(sed -n 's/.*"containerFilePath": "\([^"]*\)".*/\1/p' "$ci" | head -1)
  scheme=$(sed -n 's/.*"scheme": "\([^"]*\)".*/\1/p' "$ci" | head -1)
  platforms=$(sed -n 's/.*"platform": "\([^"]*\)".*/\1/p' "$ci" | awk '!seen[$0]++')
fi

if [ -z "$project" ]; then
  # One level down is the studio convention: Repo/App/App.xcodeproj
  set +e
  project=$(ls -d ./*.xcodeproj ./*/*.xcodeproj 2>/dev/null | head -1)
  set -e
fi

if [ -n "$project" ] && [ -z "$scheme" ]; then
  scheme_dir=$(dirname "$project")/$(basename "$project")/xcshareddata/xcschemes
  if [ -d "$scheme_dir" ]; then
    scheme=$(ls "$scheme_dir"/*.xcscheme 2>/dev/null | head -1 | xargs -n1 basename | sed 's/\.xcscheme$//')
  fi
fi

if [ -z "$platforms" ] && [ -f "$repo/Package.swift" ]; then
  pkg=""
  grep -q '\.iOS(' "$repo/Package.swift" && pkg="$pkg IOS"
  grep -q '\.macOS(' "$repo/Package.swift" && pkg="$pkg MACOS"
  grep -q '\.tvOS(' "$repo/Package.swift" && pkg="$pkg TVOS"
  grep -q '\.visionOS(' "$repo/Package.swift" && pkg="$pkg VISIONOS"
  grep -q '\.watchOS(' "$repo/Package.swift" && pkg="$pkg WATCHOS"
  platforms=$(echo "$pkg" | awk '{for(i=1;i<=NF;i++) print $i}')
fi

dest_for() {
  case $1 in
    IOS) echo "generic/platform=iOS" ;;
    MACOS) echo "generic/platform=macOS" ;;
    TVOS) echo "generic/platform=tvOS" ;;
    VISIONOS) echo "generic/platform=visionOS" ;;
    WATCHOS) echo "generic/platform=watchOS" ;;
    *) echo "" ;;
  esac
}

echo "repo:      $repo"
echo "project:   ${project:-"(none — package only)"}"
echo "scheme:    ${scheme:-"(none)"}"
echo "platforms: $(echo "$platforms" | tr '\n' ' ')"
echo

if [ "$discover_only" -eq 1 ]; then
  exit 0
fi

# --- environment -----------------------------------------------------------

if ! command -v xcodebuild >/dev/null 2>&1 && [ -n "$project" ]; then
  fail "BLOCKED-NEEDS-MAC (no xcodebuild; app scheme cannot be compiled here)"
  exit 1
fi

# --- repo tools (fast fail before xcodebuild minutes) ----------------------

if [ "$skip_tools" -eq 0 ]; then
  for tool in Tools/check-project.sh Tools/lint.sh Tools/check-docs.sh Tools/check-size.sh; do
    if [ -x "$repo/$tool" ]; then
      if "$repo/$tool"; then
        pass "$tool"
      else
        fail "$tool"
      fi
    elif [ -f "$repo/$tool" ]; then
      if sh "$repo/$tool"; then
        pass "$tool"
      else
        fail "$tool"
      fi
    else
      skip "$tool (not in repo)"
    fi
  done
fi

if [ -f "$repo/Package.swift" ]; then
  if command -v swift >/dev/null 2>&1; then
    if swift test; then
      pass "swift test"
    else
      fail "swift test"
    fi
  else
    fail "BLOCKED-NEEDS-MAC (no swift)"
  fi
fi

# Stop before spending xcodebuild minutes if the cheap gates failed.
if [ "$status" -ne 0 ]; then
  echo
  echo "stopping before platform builds (earlier gate failed)"
  exit 1
fi

# --- per-platform xcodebuild ----------------------------------------------

if [ -z "$project" ] || [ -z "$scheme" ]; then
  if [ -z "$platforms" ]; then
    skip "xcodebuild (package-only repo; swift test is the gate)"
    exit "$status"
  fi
  fail "no shared scheme / xcodeproj to build the app"
  exit 1
fi

if [ -z "$platforms" ]; then
  fail "could not discover shipping platforms"
  exit 1
fi

for plat in $platforms; do
  dest=$(dest_for "$plat")
  if [ -z "$dest" ]; then
    skip "$plat (unknown platform key)"
    continue
  fi
  echo
  echo "=== $plat ($dest) ==="
  if xcodebuild build \
      -project "$project" \
      -scheme "$scheme" \
      -destination "$dest" \
      -quiet; then
    pass "$plat"
  else
    fail "$plat ($dest)"
  fi
done

echo
if [ "$status" -eq 0 ]; then
  echo "all gates green"
else
  echo "one or more gates failed"
fi
exit "$status"
