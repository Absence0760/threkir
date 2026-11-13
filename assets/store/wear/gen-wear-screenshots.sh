#!/usr/bin/env bash
#
# Render the Wear OS store screenshots for the phone app's Play listing
# (Store presence -> Store listings -> Wear OS). Play's rule: 1:1, at least
# 384x384, app UI only, with no watch frame, added text, transparency or
# circular mask. The screens come from WearStoreScreenshotTest, which draws the
# real Compose screens under Robolectric on a large round Wear device
# (227 dp, xhdpi: 454x454) with seeded demo data; this flattens each one onto
# opaque black, the colour the watch's window is, so no alpha channel ships.
#
#   heavy bash assets/store/wear/gen-wear-screenshots.sh
#
# Deterministic: the clock, the demo route and the map tiles (off) are pinned
# in the test. Requires: a JDK 17+, and ImageMagick 7 (`magick`).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ANDROID="$REPO_ROOT/apps/watch_wear/android"
RENDERS="$ANDROID/app/build/outputs/roborazzi/store"
OUT="$SCRIPT_DIR/en-US"

command -v magick >/dev/null 2>&1 || { echo "error: 'magick' (ImageMagick 7) not on PATH" >&2; exit 1; }

rm -rf "$RENDERS"
(cd "$ANDROID" && ./gradlew :app:recordRoborazziDebug --tests 'com.runapp.watchwear.ui.store.*' --no-daemon -q)

shopt -s nullglob
renders=("$RENDERS"/*.png)
if (( ${#renders[@]} == 0 )); then
  echo "error: the test wrote no screenshots to $RENDERS" >&2
  exit 1
fi

mkdir -p "$OUT"
command rm -f "$OUT"/*.png
for src in "${renders[@]}"; do
  dst="$OUT/$(basename "$src")"
  magick "$src" -background black -alpha remove -alpha off -strip "$dst"
  read -r w h <<<"$(magick identify -format '%w %h' "$dst")"
  if (( w != h || w < 384 )); then
    echo "error: $dst is ${w}x${h}; Play needs a square of at least 384x384" >&2
    exit 1
  fi
  echo "wrote $dst (${w}x${h})"
done
