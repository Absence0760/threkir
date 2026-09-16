#!/usr/bin/env bash
#
# Regenerate the web wordmarks (apps/web/static/wordmark.svg, dark text, and
# wordmark-light.svg, white text) with the name OUTLINED as a path.
#
# They used to draw "Threkir" as live <text> in font-family system-ui, so the
# name rendered in whatever font the viewing device had: this workstation's
# Noto Sans fitted the 820-wide canvas with 7px to spare, and CI's DejaVu Sans
# ran past it and clipped the name to "Threki" (run 35134263272). An <img> SVG
# cannot load a webfont either, so outlining is the only way the lockup looks
# the same everywhere.
#
# The face is named explicitly (Noto Sans Bold, what system-ui resolved to on
# the machine the lockup was designed on) and the canvas is sized to the
# outlined text, so a different face can never be clipped again.
#
# Requires: inkscape, python3, and the Noto Sans font (fc-list).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/apps/web/static"

command -v inkscape >/dev/null 2>&1 || { echo "error: 'inkscape' not on PATH" >&2; exit 1; }
# A missing face would fall back silently and change the brand, so refuse.
fc-list : family | grep -qx "Noto Sans" || { echo "error: the Noto Sans font is not installed" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/text.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="820" height="256" viewBox="0 0 820 256">
  <text id="name" x="296" y="128" font-family="Noto Sans" font-size="150" font-weight="700"
        letter-spacing="-4" dominant-baseline="central">Threkir</text>
</svg>
SVG

inkscape "$WORK/text.svg" --export-text-to-path --export-plain-svg --export-filename="$WORK/outlined.svg" >/dev/null 2>&1
BBOX="$(inkscape "$WORK/outlined.svg" --query-id=name --query-x --query-width 2>/dev/null | tr '\n' ' ')"

python3 - "$WORK/outlined.svg" "$OUT_DIR" $BBOX <<'PY'
import math, re, sys

outlined, out_dir, x, width = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
d = ' '.join(re.findall(r'\sd="([^"]+)"', open(outlined).read()))
if not d:
    sys.exit('error: inkscape produced no outline')
# Two decimals is sub-pixel at any size the lockup is shown.
d = re.sub(r'-?\d+\.\d+', lambda m: f'{float(m.group()):.2f}'.rstrip('0').rstrip('.'), d)
canvas = math.ceil(x + width + 16)

TEMPLATE = '''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="256" viewBox="0 0 {w} 256">
  <defs>
    <linearGradient id="{grad}" x1="0" y1="0" x2="256" y2="256" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FE5932"/>
      <stop offset="0.58" stop-color="#FE5932"/>
      <stop offset="1" stop-color="#A01E77"/>
    </linearGradient>
  </defs>
  <g transform="scale(0.25)">
    <rect width="1024" height="1024" rx="180" fill="url(#{grad})"/>
    <g fill="#ffffff" fill-rule="evenodd" transform="translate(512 512) scale(7.6) translate(-54.5 -50)">
      <path d="M30 10 H44 V90 H30 Z M44 29 H58 A21 21 0 0 1 58 71 H44 Z M44 42 H56 A8 8 0 0 1 56 58 H44 Z"/>
    </g>
  </g>
  <!-- "Threkir" in Noto Sans Bold, outlined by assets/gen-wordmark.sh. -->
  <path fill="{ink}" d="{d}"/>
</svg>
'''
for name, grad, ink in [('wordmark.svg', 'tkWordmarkGrad', '#1a1a1a'),
                        ('wordmark-light.svg', 'tkWordmarkGradLight', '#ffffff')]:
    with open(f'{out_dir}/{name}', 'w') as f:
        f.write(TEMPLATE.format(w=canvas, grad=grad, ink=ink, d=d))
    print(f'wrote {out_dir}/{name} ({canvas}x256)')
PY
