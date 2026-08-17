#!/bin/sh
#
# Binary-size guardrail. Two modes:
#
#   Tools/check-size.sh                          Repo-side audit: sums everything that
#                                                ships verbatim (SwiftPM target resources
#                                                + app-target loose Resources/), reports
#                                                asset-catalog sources, flags oversized
#                                                files, enforces a budget. Toolchain-free,
#                                                so it runs in cloud sessions and gates CI
#                                                (ci_scripts/ci_post_clone.sh).
#
#   Tools/check-size.sh --app <Path.app>         Built-product breakdown (Mac): total,
#   Tools/check-size.sh --archive <P.xcarchive>  per-component (binary, frameworks, each
#                                                .appex, resource bundles, Assets.car).
#
# Why working-tree math matters: SwiftPM `.process` resources ship BYTE-FOR-BYTE
# (no actool optimization, no thinning) and are COPIED INTO EVERY TARGET that
# links the library — a resource in a package that both the app and an extension
# embed ships twice. Asset catalogs are recompiled and thinned per device, so
# their source size is only a loose proxy. Ground truth for store sizes is an
# App Thinning Size Report (this script prints the command in --app mode).
# Playbook: docs/binary-size-playbook.md.

set -e
cd "$(dirname "$0")/.."

APP_DIR="{{APP_NAME}}"

# ---- budgets (override via env) ---------------------------------------------
: "${RESOURCE_BUDGET_KB:=10240}"   # verbatim-shipped resources, total (hard fail)
: "${FILE_WARN_KB:=512}"           # single verbatim file attention threshold (warn)

fmt() { awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }'; }

# ---- built-product mode -------------------------------------------------------
if [ "$1" = "--app" ] || [ "$1" = "--archive" ]; then
  TARGET="$2"
  [ "$1" = "--archive" ] && TARGET=$(find "$2/Products" -name '*.app' | head -1)
  if [ ! -d "$TARGET" ]; then
    echo "error: no .app found at '$2'" >&2
    exit 1
  fi

  echo "== $TARGET =="
  du -sk "$TARGET" | awk '{ printf "total: %.1f MB\n", $1/1024 }'
  echo ""
  echo "-- components --"
  find "$TARGET" \( -name '*.appex' -o -name '*.framework' -o -name '*.bundle' -o -name 'Assets.car' \) \
    -exec du -sk {} \; | sort -rn | awk -v root="$TARGET/" '{ sz=$1; $1=""; sub(root, "", $0); printf "%8.1f MB %s\n", sz/1024, $0 }'
  echo ""
  echo "Assets.car contents:  xcrun assetutil --info <path-to-Assets.car>"
  echo "Per-device store sizes (ground truth): export the archive with thinning and read"
  echo "App Thinning Size Report.txt:"
  echo "  xcodebuild -exportArchive -archivePath <P.xcarchive> -exportPath /tmp/thin \\"
  echo "    -exportOptionsPlist <plist with method=development, thinning=<thin-for-all-variants>>"
  exit 0
fi

# ---- repo-side audit ----------------------------------------------------------
status=0
list=$(mktemp)
sized=$(mktemp)
trap 'rm -f "$list" "$sized"' EXIT

# Verbatim-shipped: package target resources + loose app-target Resources dirs.
# Asset catalogs and Icon Composer sources are excluded here (compiled, not verbatim).
{
  find Sources -path '*/Resources/*' -type f 2>/dev/null
  find "$APP_DIR" -path '*/Resources/*' -type f 2>/dev/null
} | grep -v '\.xcassets/' | grep -v '\.docc/' | grep -v '\.icon/' > "$list" || true

while IFS= read -r f; do
  printf '%s\t%s\n' "$(wc -c < "$f")" "$f"
done < "$list" | sort -rn > "$sized"

total=$(awk -F'\t' '{ s += $1 } END { print s + 0 }' "$sized")

echo "== Verbatim-shipped resources (SwiftPM + app-target Resources/) =="
echo "   These ship byte-for-byte; package resources duplicate into every linking target."
echo ""
head -10 "$sized" | awk -F'\t' '{ printf "%9.0f KB  %s\n", $1/1024, $2 }'
[ "$(wc -l < "$sized")" -gt 10 ] && echo "      ... $(($(wc -l < "$sized") - 10)) more files"
echo ""
echo "total: $(fmt "$total")   (budget: $(fmt $((RESOURCE_BUDGET_KB * 1024))))"

warn_bytes=$((FILE_WARN_KB * 1024))
big=$(awk -F'\t' -v w="$warn_bytes" '$1 > w { print }' "$sized")
if [ -n "$big" ]; then
  echo ""
  echo "-- files over ${FILE_WARN_KB} KB (re-encode? offload OTA? see docs/binary-size-playbook.md) --"
  echo "$big" | awk -F'\t' '{ printf "%9.0f KB  %s\n", $1/1024, $2 }'
fi

if [ "$total" -gt $((RESOURCE_BUDGET_KB * 1024)) ]; then
  echo ""
  echo "FAIL: verbatim resources exceed the ${RESOURCE_BUDGET_KB} KB budget."
  echo "      Shrink assets or consciously raise RESOURCE_BUDGET_KB in Tools/check-size.sh."
  status=1
fi

echo ""
echo "== Asset-catalog sources (compiled + thinned by actool — loose proxy, not gated) =="
find . -name '*.xcassets' -not -path './.build/*' -exec du -sk {} \; 2>/dev/null | sort -rn \
  | awk '{ sz=$1; $1=""; sub(/^ \.\//, "", $0); printf "%9.0f KB  %s\n", sz, $0 }'

roots=$(find . -maxdepth 1 -type f -size +1024k 2>/dev/null | grep -v '^\./\.' || true)
if [ -n "$roots" ]; then
  echo ""
  echo "== Repo-root files over 1 MB (clone weight, not binary weight — delete or LFS?) =="
  echo "$roots" | while IFS= read -r f; do du -k "$f"; done | awk '{ printf "%9.0f KB  %s\n", $1, $2 }'
fi

[ "$status" -eq 0 ] && { echo ""; echo "check-size: within budget."; }
exit $status
