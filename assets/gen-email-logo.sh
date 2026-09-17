#!/usr/bin/env bash
#
# Render the transactional-email header logo (96x96 PNG) from its committed
# SVG source into the web app's static dir, where the apex CloudFront
# distribution serves it at https://threkir.com/email-logo.png. Deterministic,
# idempotent, safe to re-run. Sibling of gen-x-header.sh.
#
# 96px is 3x the 32px the mail templates display it at, so it stays crisp on
# retina without a srcset — email clients don't honour one.
#
# The corners are transparent rather than filled with the header bar's teal:
# the mark has to sit on whatever colour the bar is, and baking the bar colour
# into the asset would silently rot the moment that colour changes.
#
# Requires: inkscape.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SVG="$SCRIPT_DIR/email-logo.svg"
OUT="$REPO_ROOT/apps/web/static/email-logo.png"

if [[ ! -f "$SVG" ]]; then
  echo "error: source not found at $SVG" >&2
  exit 1
fi
command -v inkscape >/dev/null 2>&1 || { echo "error: 'inkscape' not on PATH" >&2; exit 1; }

inkscape "$SVG" -w 96 -h 96 -o "$OUT" >/dev/null 2>&1
echo "wrote $OUT (96x96)"
