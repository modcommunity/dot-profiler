#!/usr/bin/env bash
# build_stamp.sh [PROJECT_DIR] -- writes PROJECT_DIR/build_id.json ({commit, branch, addons}) from the checkout.
#
# A checkout needs none: the profiler reads .git itself. Run this before a pack or an export leaves the
# checkout, so a report from that build still names its commit (DotProfilerContext.build, source "stamp").
set -euo pipefail
dir="${1:-.}"
cd "$dir"
[ -f project.godot ] || { echo "build_stamp: no project.godot in $dir" >&2; exit 2; }
commit=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
branch=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
[ -z "$(git status --porcelain 2>/dev/null | head -1)" ] || commit="$commit+dirty"
addons=""
for a in addons/*/; do
  a=${a%/}
  top=$(git -C "$(readlink -f "$a")" rev-parse --show-toplevel 2>/dev/null) || continue
  [ "$top" != "$(git rev-parse --show-toplevel 2>/dev/null)" ] || continue
  addons="$addons${addons:+, }\"$(basename "$a")\": \"$(git -C "$top" rev-parse --short=12 HEAD)\""
done
printf '{"commit": "%s", "branch": "%s", "built": "%s", "addons": {%s}}\n' \
  "$commit" "$branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$addons" > build_id.json
echo "build_stamp: $dir/build_id.json $commit"
