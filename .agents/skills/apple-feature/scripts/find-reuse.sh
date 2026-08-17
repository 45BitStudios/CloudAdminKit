#!/bin/sh
# Search studio sibling packages for an existing type / product / symbol.
# Usage: find-reuse.sh <query> [--server]
# Exit 0 even when nothing matches — empty is a valid answer after a real search.
set -eu

if [ "${1:-}" = "" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "usage: find-reuse.sh <query> [--server]" >&2
  exit 2
fi

query=$1
shift
include_server=0
for arg in "$@"; do
  case $arg in
    --server) include_server=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

root=${STUDIO45:-$HOME/Dev/Studio45}
repos="Ikigai CloudAdminKit AI"
if [ "$include_server" -eq 1 ]; then
  repos="$repos IkigaiServer"
fi

echo "query: $query"
echo "root:  $root"
echo

for repo in $repos; do
  dir="$root/$repo"
  if [ ! -d "$dir" ]; then
    echo "## $repo"
    echo "missing $dir"
    echo
    continue
  fi

  echo "## $repo"

  if [ -f "$dir/Package.swift" ]; then
    products=$(grep -E '\.library\(name:' "$dir/Package.swift" | sed -E 's/.*name: "([^"]+)".*/\1/' || true)
    if [ -n "$products" ]; then
      echo "products:"
      echo "$products" | grep -i -- "$query" || echo "(no product name matched)"
    fi
  fi

  if command -v rg >/dev/null 2>&1; then
    rg -n --type swift -m 20 -i -- \
      "$query" \
      "$dir/Sources" \
      "$dir/Package.swift" \
      2>/dev/null || echo "(no source match)"
  else
    grep -Rni --include='*.swift' -m 20 -- "$query" "$dir/Sources" "$dir/Package.swift" 2>/dev/null \
      || echo "(no source match)"
  fi
  echo
done
