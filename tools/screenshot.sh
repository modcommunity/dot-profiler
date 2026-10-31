#!/usr/bin/env bash
# Render the profiler demo (overlay plus the settings panel after a recording) to a PNG under Xvfb.
# With `menu`, render dot-menu's stock Advanced page with a profiler placed instead.
#
#   heavy -- tools/screenshot.sh <out.png> [menu]
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
OUT="$(realpath -m "$1")"
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
if [ "${2:-}" = menu ]; then
    timeout 120 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/menu_tab_shot.gd -- "$OUT"
else
    timeout 120 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/profiler_demo.tscn -- --shot "$OUT"
fi
rc=$?
kill $xpid 2>/dev/null
exit $rc
