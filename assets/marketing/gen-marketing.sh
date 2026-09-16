#!/usr/bin/env bash
#
# Regenerate the public pages' art into apps/web/static/marketing/.
#
#   terrain-hero-{960,1600,2400}.webp   landing hero, behind the product shot
#   terrain-panel-{800,1200}.webp       sign-up / sign-in brand panel
#   topo.svg                            contour lines, used as a CSS mask
#
# Deterministic: terrain.py seeds every shape, so a re-run on the same Blender
# and ImageMagick versions produces the same pictures. Not run in CI (no GPU,
# no Blender) -- same as gen-icons.sh. Commit the regenerated files.
#
#   assets/marketing/gen-marketing.sh
#   SAMPLES=32 assets/marketing/gen-marketing.sh     # quick look
#   SKIP_RENDER=1 assets/marketing/gen-marketing.sh  # re-grade the last render
#
# Requires: blender (5.x), magick (ImageMagick 7), python3.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$ROOT/apps/web/static/marketing"
OUT="$HERE/out"

for tool in blender magick python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' not on PATH" >&2; exit 1; }
done
mkdir -p "$DEST" "$OUT"

if [[ "${SKIP_RENDER:-0}" != "1" ]]; then
  SAMPLES="${SAMPLES:-128}" GRID="${GRID:-320}" \
    blender -b --factory-startup --python "$HERE/scene.py" 2>&1 | grep -E '^== |DONE|Error|Traceback'
fi

# Bloom: keep only what is already bright, blur it wide, and screen it back
# over the frame. Done here rather than in Blender's compositor so the glow is
# one legible ImageMagick line instead of a node graph that moves between
# Blender releases.
bloom() {
  magick "$1" \
    \( +clone -level 45%,100% -blur 0x10 \) -compose screen -composite \
    \( +clone -level 60%,100% -blur 0x36 \) -compose screen -composite \
    "$2"
}

bloom "$OUT/hero.png" "$OUT/hero-bloom.png"
bloom "$OUT/panel.png" "$OUT/panel-bloom.png"

for w in 960 1600 2400; do
  magick "$OUT/hero-bloom.png" -resize "${w}x" -strip -quality 74 -define webp:method=6 \
    "$DEST/terrain-hero-$w.webp"
done
for w in 800 1200; do
  magick "$OUT/panel-bloom.png" -resize "${w}x" -strip -quality 76 -define webp:method=6 \
    "$DEST/terrain-panel-$w.webp"
done

python3 "$HERE/contours.py" "$DEST/topo.svg"

ls -l "$DEST" | awk 'NR>1 {printf "  %-28s %6d KB\n", $9, $5/1024}'
