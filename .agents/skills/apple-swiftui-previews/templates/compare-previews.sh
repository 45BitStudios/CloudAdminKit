#!/bin/sh
#
# Pixel-diff current Designs/previews PNGs against a previous git revision.
#
# Default previous = last commit (HEAD). After a capture, that is "what just
# changed vs what is already committed." Pass a ref to compare against another
# point in the timeline (main, a tag, HEAD~5).
#
# Output: Designs/previews-diff/<device>/<Screen>-{light,dark}-{compare,diff}.png
#         plus summary.txt. That folder is gitignored — do not commit it.
# GitHub's PR image viewer is the committed timeline; this is the local/CI
# working copy.
#
# Usage:  Tools/compare-previews.sh [git-ref]

set -e
cd "$(dirname "$0")/.."

current="Designs/previews"
out="Designs/previews-diff"

if [ -z "${1:-}" ] && [ -n "${CI_PULL_REQUEST_TARGET_BRANCH:-}" ]; then
    ref="origin/${CI_PULL_REQUEST_TARGET_BRANCH}"
else
    ref="${1:-HEAD}"
fi

if [ ! -d "$current" ]; then
    echo "compare-previews: $current does not exist — run Tools/capture-previews.sh first"
    exit 1
fi

if ! git rev-parse --verify "$ref" >/dev/null 2>&1; then
    echo "compare-previews: git ref '$ref' not found"
    exit 1
fi

prev="$(mktemp -d "${TMPDIR:-/tmp}/previews-prev.XXXXXX")"
trap 'rm -rf "$prev"' EXIT

# Pull the previous PNGs out of git. First capture on a repo has none — every
# current screen is then reported as "new".
git ls-tree -r --name-only "$ref" -- Designs/previews 2>/dev/null | while read -r path; do
    case "$path" in
        *.png) ;;
        *) continue ;;
    esac
    rel="${path#Designs/previews/}"
    dest="$prev/$rel"
    mkdir -p "$(dirname "$dest")"
    git show "$ref:$path" > "$dest" 2>/dev/null || true
done

mkdir -p "$out"
find "$out" -type f \( -name '*.png' -o -name 'summary.txt' \) -delete 2>/dev/null || true

echo "Comparing $current to $ref"
swift Tools/compare-previews.swift --previous "$prev" --current "$current" --output "$out"
echo "compare-previews: wrote $out"
