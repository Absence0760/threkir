#!/usr/bin/env bash
# Render Grisnir's app exports from the mascot's Blender model and write them
# where the apps read them (apps/web/static/brand/grisnir/README.md lists each
# file and where it is used).
#
#   bash scripts/brand/render_mascot.sh ~/github/social/brand/threkir/mascot/grisnir.blend
#
# The model lives in the owner's private brand repo; nothing here needs it
# except a re-render, and CI never runs this. Blender renders each pose at the
# size it ships at (render_mascot.py); ImageMagick 7 only trims the transparent
# margin, strips metadata and writes the WebP twin. Nothing is downscaled.
set -euo pipefail

BLEND=${1:?usage: render_mascot.sh <path to grisnir.blend>}
[ -f "$BLEND" ] || { echo "no such file: $BLEND" >&2; exit 1; }
command -v magick >/dev/null || { echo "needs ImageMagick 7 (magick)" >&2; exit 1; }

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${GRISNIR_WORK:-$HOME/.cache/grisnir-render}
RAW=$WORK/raw
mkdir -p "$RAW"
# Big renders stay off /tmp, which is a RAM tmpfs on the owner's machine.
export TMPDIR=$WORK

heavy blender -b "$BLEND" --python "$ROOT/scripts/brand/render_mascot.py" -- --out "$RAW"

WEB=$ROOT/apps/web/static/brand/grisnir
mkdir -p "$WEB"
export_png() {
  magick "$RAW/$1.png" -trim +repage -bordercolor none -border 2 -strip \
    -define png:exclude-chunks=date,time -define png:compression-level=9 \
    "PNG32:$WEB/grisnir-$1.png"
}
# The badge is only ever drawn as a PNG (an <img> captured by html-to-image,
# a data URI inside an SVG, a Flutter asset); the rest-day art is a <picture>.
export_png badge-256
for name in rest-192 rest-384; do
  export_png "$name"
  magick "$WEB/grisnir-$name.png" -define webp:lossless=true -define webp:method=6 \
    "$WEB/grisnir-$name.webp"
done

# The phones bundle the two they draw; the twin carries identical bytes.
for app in mobile_android mobile_ios; do
  dir=$ROOT/apps/$app/assets/brand/grisnir
  mkdir -p "$dir"
  command cp -f "$WEB/grisnir-badge-256.png" "$WEB/grisnir-rest-384.png" "$dir/"
done

# Share cards rasterised from an SVG string (the /og/* unfurls in a Lambda,
# the recap image in the browser) can only carry the image inline.
node "$ROOT/scripts/brand/gen_grisnir_badge_module.mjs"

magick identify -format '%f %wx%h %b\n' "$WEB"/grisnir-*.png "$WEB"/grisnir-*.webp
