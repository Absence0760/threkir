#!/usr/bin/env python3
"""Compose the captioned store panels from the raw captures.

Reads panels.json (panel order, which capture each uses, the target sizes) and
every captions/<locale>.json, fills templates/panel.svg once per panel, target
and locale, and renders it with Inkscape. Writes
<out>/<locale>/<target>/<NN>-<panel>.png, numbered in listing order.

Every output is checked before the script exits 0: the exact target size, and
8-bit RGB with no alpha channel, which is what Play asks for (24-bit PNG) and
what App Store Connect accepts. Run it through gen-store-screenshots.sh, which
points fontconfig at the repo's Manrope first.

Standard library only:
  python3 assets/store/render_panels.py --captures DIR --out DIR [--locale en]
"""
from __future__ import annotations

import argparse
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from string import Template
from xml.sax.saxutils import escape

HERE = Path(__file__).resolve().parent

# Geometry as fractions of the panel width (W) or height (H), so the same
# proportions hold at 1080x1920 and 1320x2868.
TOP_MARGIN_H = 0.07
HEADLINE_SIZE_W = 0.074
HEADLINE_LEADING = 1.12
SUBLINE_SIZE_W = 0.034
SUBLINE_GAP_W = 0.035
PHONE_GAP_H = 0.045
PHONE_WIDTH_W = 0.80
BEZEL_W = 0.018
PHONE_RADIUS_OF_PHONE = 0.11


def png_header(path: Path) -> tuple[int, int, int, int]:
    """(width, height, bit depth, colour type) from a PNG's IHDR chunk."""
    with path.open("rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    return width, height, head[24], head[25]


def layout(width: int, height: int, lines: int, capture_w: int, capture_h: int) -> dict:
    headline_size = round(width * HEADLINE_SIZE_W)
    subline_size = round(width * SUBLINE_SIZE_W)
    first_baseline = round(height * TOP_MARGIN_H + headline_size)
    line_step = round(headline_size * HEADLINE_LEADING)
    last_baseline = first_baseline + line_step * (lines - 1)
    subline_baseline = round(last_baseline + width * SUBLINE_GAP_W + subline_size)
    phone_w = round(width * PHONE_WIDTH_W)
    bezel = round(width * BEZEL_W)
    screen_w = phone_w - 2 * bezel
    screen_h = round(screen_w * capture_h / capture_w)
    phone_h = screen_h + 2 * bezel
    phone_x = (width - phone_w) // 2
    phone_y = round(subline_baseline + height * PHONE_GAP_H)
    phone_r = round(phone_w * PHONE_RADIUS_OF_PHONE)
    return {
        "width": width,
        "height": height,
        "headline_size": headline_size,
        "headline_tracking": round(-headline_size * 0.02, 2),
        "subline_size": subline_size,
        "first_baseline": first_baseline,
        "line_step": line_step,
        "subline_baseline": subline_baseline,
        "phone_x": phone_x,
        "phone_y": phone_y,
        "phone_w": phone_w,
        "phone_h": phone_h,
        "phone_r": phone_r,
        "phone_stroke": max(2, round(width * 0.002)),
        "screen_x": phone_x + bezel,
        "screen_y": phone_y + bezel,
        "screen_w": screen_w,
        "screen_h": screen_h,
        "screen_r": max(0, phone_r - bezel),
    }


def fill(template: Template, geo: dict, caption: dict, capture_href: str) -> str:
    cx = geo["width"] / 2
    headline = "".join(
        f'<tspan x="{cx}" y="{geo["first_baseline"] + i * geo["line_step"]}">{escape(line)}</tspan>'
        for i, line in enumerate(caption["headline"])
    )
    subline = f'<tspan x="{cx}" y="{geo["subline_baseline"]}">{escape(caption["subline"])}</tspan>'
    return template.substitute(
        {k: str(v) for k, v in geo.items()},
        headline=headline,
        subline=subline,
        capture=escape(capture_href, {'"': "&quot;"}),
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--captures", required=True, type=Path, help="directory of raw captures")
    ap.add_argument("--out", required=True, type=Path, help="directory to write panels into")
    ap.add_argument("--locale", action="append", help="only these locales (default: every captions/*.json)")
    args = ap.parse_args()

    if shutil.which("inkscape") is None:
        print("error: 'inkscape' not on PATH", file=sys.stderr)
        return 1

    config = json.loads((HERE / "panels.json").read_text())
    template = Template((HERE / "templates" / "panel.svg").read_text())
    locales = args.locale or sorted(p.stem for p in (HERE / "captions").glob("*.json"))
    panels = config["panels"]

    problems = []
    captures = {}
    for panel in panels:
        path = args.captures / panel["capture"]
        if not path.is_file():
            problems.append(f"missing capture {path}")
            continue
        w, h, _, _ = png_header(path)
        captures[panel["id"]] = (path.resolve(), w, h)
    captions = {}
    for locale in locales:
        source = HERE / "captions" / f"{locale}.json"
        if not source.is_file():
            problems.append(f"no captions for locale {locale!r} ({source})")
            continue
        captions[locale] = json.loads(source.read_text())
        for panel in panels:
            c = captions[locale].get(panel["id"])
            if not c or not c.get("headline") or not c.get("subline"):
                problems.append(f"captions/{locale}.json has no headline and subline for {panel['id']!r}")
    if problems:
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        return 1

    written = 0
    with tempfile.TemporaryDirectory() as work:
        work_dir = Path(work)
        for locale in locales:
            for target, size in config["targets"].items():
                dest = args.out / locale / target
                dest.mkdir(parents=True, exist_ok=True)
                for index, panel in enumerate(panels, start=1):
                    capture, cw, ch = captures[panel["id"]]
                    caption = captions[locale][panel["id"]]
                    geo = layout(size["width"], size["height"], len(caption["headline"]), cw, ch)
                    svg = work_dir / f"{locale}-{target}-{panel['id']}.svg"
                    svg.write_text(fill(template, geo, caption, capture.as_uri()))
                    png = dest / f"{index:02d}-{panel['id']}.png"
                    subprocess.run(
                        [
                            "inkscape", str(svg),
                            "--export-type=png",
                            f"--export-filename={png}",
                            f"--export-width={size['width']}",
                            f"--export-height={size['height']}",
                            "--export-background=#000000",
                            "--export-background-opacity=1",
                            "--export-png-color-mode=RGB_8",
                        ],
                        check=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    w, h, depth, colour = png_header(png)
                    if (w, h) != (size["width"], size["height"]) or depth != 8 or colour != 2:
                        print(
                            f"error: {png} is {w}x{h}, bit depth {depth}, colour type {colour}; "
                            f"expected {size['width']}x{size['height']} 8-bit RGB (type 2)",
                            file=sys.stderr,
                        )
                        return 1
                    print(f"wrote {png}")
                    written += 1
    print(f"{written} panels")
    return 0


if __name__ == "__main__":
    sys.exit(main())
