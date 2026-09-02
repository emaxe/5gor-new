#!/usr/bin/env bash
# Прогон тестов headless. Usage: tools/run_tests.sh [tests/unit ...]
set -euo pipefail
GODOT="${GODOT_PATH:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARGS=()
if [ $# -eq 0 ]; then
  ARGS=(-a tests/unit -a tests/integration)
else
  for p in "$@"; do ARGS+=(-a "$p"); done
fi
exec "$GODOT" --headless --path "$ROOT" \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode "${ARGS[@]}"
