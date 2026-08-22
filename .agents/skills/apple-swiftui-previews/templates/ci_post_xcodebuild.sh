#!/bin/sh
#
# After the Screens scheme builds on Xcode Cloud, render design PNGs and copy
# them into the result bundle so they show up as workflow artifacts.
#
# Existing CI / TestFlight workflows use other schemes and skip this.

set -e

scheme="${CI_XCODE_SCHEME:-}"
workflow="${CI_WORKFLOW:-}"
case "$scheme $workflow" in
  *Screens*|*Design*) ;;
  *) exit 0 ;;
esac

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
  echo "xcodebuild failed; skipping screenshot capture."
  exit 0
fi

cd "${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE/repository}"

echo "Capturing design screenshots (scheme=$scheme workflow=$workflow)"
Tools/capture-previews.sh

if [ -x Tools/compare-previews.sh ]; then
  echo "Comparing screenshots to previous revision"
  Tools/compare-previews.sh || echo "compare-previews: skipped (no previous PNGs or git ref)"
fi

if [ -n "${CI_RESULT_BUNDLE_PATH:-}" ]; then
  dest="$CI_RESULT_BUNDLE_PATH/Screens"
  mkdir -p "$dest"
  cp -R Designs/previews/. "$dest/"
  if [ -d Designs/previews-diff ]; then
    mkdir -p "$dest/diff"
    cp -R Designs/previews-diff/. "$dest/diff/"
  fi
  echo "Copied $(ls Designs/previews | wc -l | tr -d ' ') PNGs to $dest"
fi
