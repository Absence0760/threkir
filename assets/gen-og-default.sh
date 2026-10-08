#!/usr/bin/env bash
#
# Render the default Open Graph image (1200x630 PNG, apps/web/static/og-default.png)
# from its committed SVG source. Deterministic, idempotent, safe to re-run.
# Sibling of gen-feature-graphic.sh.
#
# Requires: inkscape, and packages/ui_kit/fonts (gen-manrope.py) for the
# Manrope text.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SVG="$SCRIPT_DIR/og-default.svg"
OUT="$REPO_ROOT/apps/web/static/og-default.png"

command -v inkscape >/dev/null 2>&1 || { echo "error: 'inkscape' not on PATH" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=assets/fonts/manrope-fontconfig.sh
source "$SCRIPT_DIR/fonts/manrope-fontconfig.sh"

inkscape "$SVG" -w 1200 -h 630 -o "$OUT" >/dev/null 2>&1
magick "$OUT" -strip +dither -colors 256 -define png:compression-level=9 "PNG8:$OUT"
echo "wrote $OUT (1200x630)"
