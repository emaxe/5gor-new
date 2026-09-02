#!/usr/bin/env bash
# Снимки сцены во всех трёх рендерерах для визуальной сверки.
# Usage: tools/capture_style.sh <res://scene.tscn> [outdir] [view]
set -euo pipefail
GODOT="${GODOT_PATH:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="${1:-res://tests/scenes/test_style.tscn}"
OUT="${2:-/tmp/5gor_shots}"
VIEW="${3:-0}"
mkdir -p "$OUT"
NAME="$(basename "${SCENE%.tscn}")"
for m in forward_plus mobile gl_compatibility; do
  "$GODOT" --path "$ROOT" --rendering-method "$m" tools/capture_runner.tscn -- \
    --scene "$SCENE" --out "$OUT/${NAME}_${VIEW}_${m}.png" \
    --frames 45 --size 960x540 --view "$VIEW" 2>&1 \
    | grep -E "снимок|SHADER ERROR" | sed "s/^/[$m] /" || true
done
echo "готово: $OUT"
