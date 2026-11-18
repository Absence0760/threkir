#!/usr/bin/env python3
"""Compose the captioned store panels from the raw captures.

Reads panels.json (the listing order, each panel's ground, capture theme,
crops, callout and claims, the target sizes and the Play experiment's
variants), every captions/<locale>.json, and per target a capture directory
holding the PNGs, bounds.json (where each section sits in each capture) and
numbers.json (the numbers the screens show). Builds one SVG per panel, target
and locale, renders it with Inkscape, and writes
<out>/<locale>/<target>/<NN>-<panel>.png, numbered in listing order, plus
<out>/<locale>/<target>-<variant>/ for each experiment variant.

It fails, writing nothing for that locale, when a caption types a number,
names a number its panel's screen does not show, makes a claim the numbers do
not support (store_numbers.py), breaks a store listing rule, needs a headline
smaller than 0.094 of the panel width to fit, or puts text on a ground at
under 4.5:1. Every PNG is checked for the exact target size and 8-bit RGB
with no alpha before the script exits 0. Run it through
gen-store-screenshots.sh, which points fontconfig at the repo's Manrope.

Standard library only:
  python3 assets/store/render_panels.py --captures play-phone=DIR \\
      [--captures appstore-6.9=DIR] --out DIR [--locale en] [--target T] \\
      [--appstore-from-android] [--keep-svg]
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
from font_metrics import text_width  # noqa: E402
from store_numbers import DataError, Numbers, resolve_caption  # noqa: E402

HERE = Path(__file__).resolve().parent

# Layout, from the concept C style frames. Lengths are Play panel px and
# scale with k = W / 1080, so both targets keep the same proportions.
HEAD_W = 0.104            # headline size, fraction of W
HEAD_MIN_W = 0.094        # below this a line must be rewritten, not shrunk
KICKER_W = 0.048
SUBLINE_W = 0.034
MARGIN = 80               # headline x
LEAD = 1.07               # line step, in headline sizes
FIRST_BASELINE = 268      # the same on every panel
KICKER_RISE = 1.14        # kicker baseline above the first, in headline sizes
CARD_X, CARD_Y, CARD_BOTTOM = 60, 470, 80
CARD_RADIUS = 44
FADE = 150
OVERHANG = 24             # a lifted element's reach past the card, each side
SHADOW_BLUR, SHADOW_DY = 16, 10
MAX_EMPTY = 200           # more bare ground than this under a card is reported
MIN_CONTRAST = 4.5

GROUND_TEXT = {
    "dark": {"headline": "#FFFFFF", "kicker": "#B9A7E8", "accent": "#EC8B7A"},
    "ramp": {"headline": "#FFFFFF", "kicker": "#FFFFFF", "accent": None},
    "light": {"headline": "#1A1722", "kicker": "#5B4B8A", "accent": "#C24E24"},
}
CARD_EDGE = {"dark": ("#FFFFFF", 0.12), "ramp": None, "light": ("#1A1722", 0.10)}
SHADOW = {"dark": ("#000000", 0.55), "ramp": ("#000000", 0.45), "light": ("#1A1722", 0.16)}

# The app's own colour roles (packages/ui_kit app_theme.dart), for the
# callout rows the renderer draws from numbers.json.
THEMES = {
    "dark": dict(bg="#121117", on="#F3F1F7", muted="#C6C2CF", primary="#F08A5D", on_primary="#1A0E08",
                 danger="#EC8B7A", on_danger="#121117", success="#8CC49B", on_success="#121117",
                 warning="#E6A23C", on_warning="#121117", container="#36323F", outline="#736D85"),
    "light": dict(bg="#FAF9FB", on="#1A1722", muted="#504B5B", primary="#C24E24", on_primary="#FFFFFF",
                  danger="#A93B2E", on_danger="#FAF9FB", success="#2E6B3C", on_success="#FAF9FB",
                  warning="#8A5712", on_warning="#FAF9FB", container="#E6E1E9", outline="#8A8496"),
}
CONFIDENCE_ROLE = {"high": "success", "moderate": "warning", "low": "danger"}
SLOWEST_BAR_FRACTION = 0.4  # run_detail_screen.dart: slowest = 40% of the lane
DIM_OPACITY = 0.55          # spec open issue 1: dim the context, not the hero


class RenderError(Exception):
    pass


# ----------------------------------------------------------------- utilities

def png_header(path: Path) -> tuple[int, int, int, int]:
    """(width, height, bit depth, colour type) from a PNG's IHDR chunk."""
    with path.open("rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise RenderError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    return width, height, head[24], head[25]


def f1(v: float) -> str:
    return f"{v:.1f}"


def text(x, y, s, size, weight, fill, anchor="start", tracking=0.0):
    ls = f' letter-spacing="{tracking:.2f}"' if tracking else ""
    return (f'<text x="{f1(x)}" y="{f1(y)}" font-family="Manrope" font-size="{f1(size)}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{ls}>{escape(s)}</text>')


def rect(x, y, w, h, fill, rx=0.0, extra=""):
    return (f'<rect x="{f1(x)}" y="{f1(y)}" width="{f1(w)}" height="{f1(h)}" rx="{f1(rx)}" '
            f'fill="{fill}"{extra}/>')


def mid_baseline(top, box_h, size):
    """The baseline that centres Manrope's figures and caps (cap height ~0.72 em)."""
    return top + box_h / 2 + 0.36 * size


# -------------------------------------------------------------- the grounds

def _hex(c: str) -> tuple[float, float, float]:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _stops(stops, t):
    """Colour and opacity at t along [(offset, hex, opacity), ...]."""
    if t <= stops[0][0]:
        return _hex(stops[0][1]), stops[0][2]
    for (o0, c0, a0), (o1, c1, a1) in zip(stops, stops[1:]):
        if t <= o1:
            u = (t - o0) / (o1 - o0) if o1 > o0 else 1.0
            a, b = _hex(c0), _hex(c1)
            return tuple(a[i] + (b[i] - a[i]) * u for i in range(3)), a0 + (a1 - a0) * u
    return _hex(stops[-1][1]), stops[-1][2]


def _over(base, colour, alpha):
    return tuple(base[i] * (1 - alpha) + colour[i] * alpha for i in range(3))


NIGHT = [(0, "#241A35", 1), (0.6, "#121117", 1)]
GLOW = [(0, "#C24E24", 0.42), (0.45, "#A8426A", 0.22), (1, "#5B4B8A", 0)]
RAMP = [(0, "#C24E24", 1), (0.5, "#A8426A", 1), (1, "#5B4B8A", 1)]
DAY = [(0.12, "#FFFFFF", 1), (1, "#EEE8F4", 1)]
DAYGLOW = [(0, "#F08A5D", 0.32), (0.5, "#A8426A", 0.12), (1, "#5B4B8A", 0)]


def ground_colour(ground: str, W: int, H: int, x: float, y: float):
    """The ground's colour at (x, y), computed from the same gradients the SVG
    draws, so text contrast is measured without rendering."""
    if ground == "dark":
        base, _ = _stops(NIGHT, y / H)
        c, a = _stops(GLOW, math.hypot(x - 0.92 * W, y + 0.03 * H) / (0.95 * W))
        return _over(base, c, a)
    if ground == "ramp":
        base, _ = _stops(RAMP, (x * W + y * H) / (W * W + H * H))
        return _over(base, (0, 0, 0), 0.35 * y / H)
    base, _ = _stops(DAY, y / H)
    c, a = _stops(DAYGLOW, math.hypot(x - W, y - H) / (1.15 * W))
    return _over(base, c, a)


def luminance(rgb) -> float:
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def worst_contrast(ground, W, H, box, colour) -> float:
    x, y, w, h = box
    worst = 99.0
    for i in range(13):
        for j in range(7):
            bg = ground_colour(ground, W, H, x + w * i / 12, y + h * j / 6)
            worst = min(worst, contrast(_hex(colour), bg))
    return round(worst, 2)


def ground_defs(ground: str, W: int, H: int) -> str:
    def lin(gid, x2, y2, stops, units="userSpaceOnUse"):
        s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        return f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}" gradientUnits="{units}">{s}</linearGradient>'

    def rad(gid, cx, cy, r, stops):
        s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        return (f'<radialGradient id="{gid}" cx="{f1(cx)}" cy="{f1(cy)}" r="{f1(r)}" '
                f'gradientUnits="userSpaceOnUse">{s}</radialGradient>')

    if ground == "dark":
        defs = lin("g1", 0, H, NIGHT) + rad("g2", 0.92 * W, -0.03 * H, 0.95 * W, GLOW)
    elif ground == "ramp":
        defs = lin("g1", W, H, RAMP) + lin("g2", 0, 1, [(0, "#000000", 0), (1, "#000000", 0.35)],
                                           "objectBoundingBox")
    else:
        defs = lin("g1", 0, H, DAY) + rad("g2", W, H, 1.15 * W, DAYGLOW)
    k = W / 1080
    colour, opacity = SHADOW[ground]
    # Inkscape ignores feDropShadow, so the lift is built from its parts.
    lift = (f'<filter id="lift" x="-10%" y="-20%" width="120%" height="160%">'
            f'<feGaussianBlur in="SourceAlpha" stdDeviation="{f1(SHADOW_BLUR * k)}"/>'
            f'<feOffset dy="{f1(SHADOW_DY * k)}" result="b"/>'
            f'<feFlood flood-color="{colour}" flood-opacity="{opacity}"/>'
            '<feComposite in2="b" operator="in" result="s"/>'
            '<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    return defs + lift


# --------------------------------------------------------------- captures

@dataclass
class Capture:
    name: str
    path: Path
    width: int
    height: int
    dpr: float
    theme: str
    sections: dict[str, tuple[float, float, float, float]]
    colours: dict[str, str] = field(default_factory=dict)

    def section(self, name: str):
        return self.sections.get(name)


def load_capture_dir(directory: Path) -> tuple[dict[str, Capture], Numbers]:
    bounds_path = directory / "bounds.json"
    numbers_path = directory / "numbers.json"
    for p in (bounds_path, numbers_path):
        if not p.is_file():
            raise RenderError(f"{p} is missing; the capture suite writes it beside the PNGs (README.md)")
    bounds = json.loads(bounds_path.read_text())
    if bounds.get("schema") != 1:
        raise RenderError(f"{bounds_path}: schema should be 1")
    captures = {}
    for name, entry in bounds.get("captures", {}).items():
        path = directory / entry.get("file", f"{name}.png")
        if not path.is_file():
            raise RenderError(f"{bounds_path} names {path.name}, which is not in {directory}")
        w, h, _, _ = png_header(path)
        sections = {}
        for sname, r in entry.get("sections", {}).items():
            if len(r) != 4 or r[2] <= 0 or r[3] <= 0:
                raise RenderError(f"{bounds_path}: {name}.{sname} should be [x, y, w, h] with a positive size")
            if r[0] < 0 or r[1] < 0 or r[0] + r[2] > w + 0.5 or r[1] + r[3] > h + 0.5:
                raise RenderError(f"{bounds_path}: {name}.{sname} {r} runs outside the {w}x{h} capture")
            sections[sname] = tuple(float(v) for v in r)
        if entry.get("theme") not in THEMES:
            raise RenderError(f"{bounds_path}: {name}.theme should be dark or light")
        captures[name] = Capture(name, path.resolve(), w, h, float(entry["dpr"]), entry["theme"], sections,
                                 entry.get("colours", {}))
    try:
        numbers = Numbers(json.loads(numbers_path.read_text()), str(numbers_path))
    except DataError as e:
        raise RenderError(str(e)) from e
    return captures, numbers


# ------------------------------------------------------------ the stack

@dataclass
class ImagePiece:
    capture: Capture
    x0: float
    y0: float
    x1: float
    y1: float
    scale: float
    dims: list[tuple[float, float]]

    @property
    def height(self):
        return (self.y1 - self.y0) * self.scale


@dataclass
class LiftPiece:
    """A captured card lifted out of the list at its captured scale, on a box
    of its own colour that overhangs the panel card on both sides."""
    capture: Capture
    box: tuple[float, float, float, float]  # the section, capture px
    scale: float
    radius: float
    fill: str | None  # the card's own colour, widening it past its capture

    @property
    def height(self):
        return self.box[3] * self.scale


@dataclass
class GapPiece:
    height: float


@dataclass
class CalloutPiece:
    kind: str
    height: float
    s: float          # panel px per dp
    margin: float
    fill: str | None = None  # the box colour, when the row sat on a card


def _crop_rect(crop: dict, cap: Capture, target: str, dpr_px):
    """(x0, y0, x1, y1) in capture px, from sections or the explicit fallback
    rect; None when an optional crop's sections are missing."""
    first, last = cap.section(crop.get("from", "")), cap.section(crop.get("to", crop.get("from", "")))
    if first and last:
        top, bottom = first[1], last[1] + last[3]
        # A pad stops at a neighbouring section, so it never shows a sliver
        # of the card above or the title below.
        above = [r[1] + r[3] for r in cap.sections.values() if r[1] + r[3] <= top + 0.5]
        below = [r[1] for r in cap.sections.values() if r[1] >= bottom - 0.5]
        y0 = max([top - crop.get("pad_top_dp", 0) * dpr_px, 0.0] + above)
        y1 = min([bottom + crop.get("pad_bottom_dp", 0) * dpr_px, float(cap.height)] + below)
        return 0.0, y0, float(cap.width), y1
    fallback = crop.get("rect")
    if isinstance(fallback, dict):
        fallback = fallback.get(target)
    if fallback:
        x, y, w, h = fallback
        return float(x), float(y), float(x + w), float(y + h)
    if crop.get("optional"):
        return None
    raise RenderError(f"capture {cap.name!r} has no section {crop.get('from')!r}/{crop.get('to')!r} "
                      f"and the crop gives no fallback rect")


def _rows(cap: Capture, prefix: str, y0: float, y1: float):
    """The `<prefix><n>` sections inside [y0, y1], by n."""
    found = []
    for name, r in cap.sections.items():
        if name.startswith(prefix) and name[len(prefix):].isdigit() and r[1] >= y0 - 0.5 and r[1] + r[3] <= y1 + 0.5:
            found.append((int(name[len(prefix):]), r))
    return sorted(found)


def build_stack(panel: dict, target: str, captures: dict[str, Capture], values: dict, card_w: float, k: float):
    crops = panel["crops"]
    if isinstance(crops, dict):
        crops = crops.get(target, crops.get("default"))
    callout = panel.get("callout")
    callout_section = callout["section"].format_map(_Dotted(values)) if callout else None
    callout_done = False
    pieces = []
    for crop in crops:
        cap = captures.get(crop["capture"])
        if cap is None:
            if crop.get("optional"):
                continue
            raise RenderError(f"{panel['id']}: no capture {crop['capture']!r} in bounds.json")
        if cap.theme != panel["theme"]:
            raise RenderError(f"{panel['id']}: capture {cap.name!r} is {cap.theme}, the panel needs {panel['theme']}")
        if panel.get("column_dp") and abs(cap.width / cap.dpr - panel["column_dp"]) > 1:
            raise RenderError(f"{panel['id']}: capture {cap.name!r} is {cap.width / cap.dpr:.0f} dp wide; "
                              f"the panel needs {panel['column_dp']} dp (spec: screen scale)")
        r = _crop_rect(crop, cap, target, cap.dpr)
        if r is None:
            continue
        x0, y0, x1, y1 = r
        if crop.get("gap_px") and pieces:
            pieces.append(GapPiece(crop["gap_px"] * k))
        scale = card_w / (x1 - x0)
        if crop.get("lift"):
            sec = cap.section(crop["from"])
            if sec is None:
                raise RenderError(f"{panel['id']}: a lifted crop needs the section {crop['from']!r}")
            pieces.append(LiftPiece(cap, sec, scale, 12 * cap.dpr * scale, cap.colours.get(crop["from"])))
            continue
        # Cut-outs inside this crop: split rows outside the window, and the
        # row a callout replaces. Each is (top, bottom, replacement or None).
        cuts = []
        window = crop.get("window")
        if window:
            rows = _rows(cap, window.get("prefix", "split-row-"), y0, y1)
            if len(rows) > window["max"]:
                centre = int(values["slowest.km"])
                keep = range(centre - window["before"], centre + window["after"] + 1)
                drop = [r for n, r in rows if n not in keep]
                for r in drop:
                    cuts.append((r[1], r[1] + r[3], None))
        if callout and not callout_done:
            sec = cap.section(callout_section)
            if sec and y0 <= sec[1] and sec[1] + sec[3] <= y1:
                s = cap.dpr * scale
                h, margin = callout_height(callout, s)
                cuts.append((sec[1], sec[1] + sec[3],
                             CalloutPiece(callout["kind"], h, s, margin, cap.colours.get(callout_section))))
                callout_done = True
        cuts.sort(key=lambda c: c[0])
        dim_prefixes = panel.get("dim", [])
        cursor = y0
        for top, bottom, replacement in cuts + [(y1, y1, None)]:
            if top > cursor:
                dims = [(r[1], r[1] + r[3]) for p in dim_prefixes for _, r in _rows(cap, p, cursor, top)]
                pieces.append(ImagePiece(cap, x0, cursor, x1, top, scale, dims))
            if replacement is not None:
                pieces.append(replacement)
            cursor = max(cursor, bottom)
    if callout and not callout_done:
        raise RenderError(f"{panel['id']}: the callout's row {callout_section!r} is in none of the panel's crops")
    return pieces


class _Dotted(dict):
    """str.format_map over 'a.b' keys: '{slowest.km}' reads values['slowest.km']."""

    def __init__(self, values):
        super().__init__()
        self.values = values

    def __missing__(self, key):
        return _Attr(self.values, key)


class _Attr:
    def __init__(self, values, prefix):
        self.values, self.prefix = values, prefix

    def __getattr__(self, name):
        key = f"{self.prefix}.{name}"
        if key not in self.values:
            raise RenderError(f"unknown placeholder {{{key}}} in a callout section name")
        return self.values[key]


# ------------------------------------------------------------- callouts

def callout_height(callout: dict, s: float) -> tuple[float, float]:
    mag = callout["scale"]
    if callout["kind"] == "split":
        bar_h = 26 * s * mag * 0.9
        return bar_h + 2 * (4 * s * mag * 0.5) + 14 * s, 6 * s
    if callout["kind"] == "predictor":
        return 20 * s * mag + 2 * 10 * s, 0.0
    raise RenderError(f"unknown callout kind {callout['kind']!r}")


def _outline(T: dict, s: float) -> str:
    return f' stroke="{T["outline"]}" stroke-width="{f1(1.2 * s)}"'


def split_callout(piece: CalloutPiece, top: float, x: float, w: float, mag: float, numbers: Numbers, T: dict):
    """The slowest km, rebuilt at `mag` times its row and lifted out of the
    list. The duration lane is dropped: for a whole km it repeats the pace."""
    s = piece.s
    m_t = mag * 0.88
    box_h = piece.height
    out = [f'<g filter="url(#lift)">{rect(x, top, w, box_h, T["bg"], 12 * s, _outline(T, s))}</g>']
    slow = numbers.slowest
    label = numbers.labels.get("grade_adj", "Grade-adj.")
    inner_l, inner_r = x + 20 * s, x + w - 20 * s
    tick_size, lbl_size, gap_size, lab_size = 14 * s * m_t, 11 * s * 1.7, 14 * s * m_t, 12 * s * m_t
    gap_w = max(text_width(slow["gap"], gap_size, 400), text_width(label, lbl_size, 500, 0.5 * s))
    tick_w = text_width(str(slow["km"]), tick_size, 600) + 10 * s
    bar_l = inner_l + tick_w + 8 * s
    bar_r = inner_r - gap_w - 12 * s
    lab_w = text_width(slow["raw"], lab_size, 600) + 2 * 8 * s * 1.6
    bar_w = max((bar_r - bar_l) * SLOWEST_BAR_FRACTION, lab_w)
    bar_h = 26 * s * mag * 0.9
    bt = top + (box_h - bar_h) / 2
    out.append(text(inner_l + tick_w / 2 - 5 * s, mid_baseline(bt, bar_h, tick_size), str(slow["km"]),
                    tick_size, 600, T["muted"], "middle"))
    out.append(rect(bar_l, bt, bar_w, bar_h, T["danger"], 4 * s * 1.8))
    out.append(text(bar_l + 8 * s * 1.6, mid_baseline(bt, bar_h, lab_size), slow["raw"], lab_size, 600,
                    T["on_danger"]))
    value_base = bt + bar_h * 0.9
    out.append(text(inner_r, value_base, slow["gap"], gap_size, 400, T["muted"], "end"))
    out.append(text(inner_r, value_base - gap_size * 0.86 - 6 * s, label, lbl_size, 500, T["muted"], "end",
                    0.5 * s))
    return "\n".join(out)


def predictor_callout(piece: CalloutPiece, top: float, x: float, w: float, mag: float, numbers: Numbers,
                      T: dict, fill: str):
    """The Half rung, rebuilt at `mag` times and lifted, all four columns
    kept, the confidence chip in its own colour."""
    s = piece.s
    rung = numbers.rungs["half"]
    out = [f'<g filter="url(#lift)">{rect(x, top, w, piece.height, fill, 12 * s, _outline(T, s))}</g>']
    inner_l, inner_r = x + 20 * s, x + w - 20 * s
    while True:
        size, chip_size = 14 * s * mag, 11 * s * mag
        chip_w = text_width(rung["confidence_label"], chip_size, 700) + 2 * 8 * s * mag
        widths = [text_width(rung["distance"], size, 600), text_width(rung["time"], size, 700),
                  text_width(rung["pace"], size, 400), chip_w]
        natural = sum(widths) + 3 * 12 * s
        if natural <= inner_r - inner_l or mag < 1.0:
            break
        mag *= 0.97
    spare = (inner_r - inner_l) - natural
    flex = [3, 3, 3, 4]
    row_h = 20 * s * mag
    row_top = top + (piece.height - row_h) / 2
    cx = inner_l
    styles = [(rung["distance"], 600), (rung["time"], 700), (rung["pace"], 400)]
    for i, (value, weight) in enumerate(styles):
        out.append(text(cx, mid_baseline(row_top, row_h, size), value, size, weight, T["on"]))
        cx += widths[i] + 12 * s + spare * flex[i] / sum(flex)
    role = CONFIDENCE_ROLE[rung["confidence"]]
    chip_h = (16 + 4) * s * mag * 0.8
    chip_top = row_top + (row_h - chip_h) / 2
    out.append(rect(cx, chip_top, chip_w, chip_h, T[role], chip_h / 2))
    out.append(text(cx + 8 * s * mag, mid_baseline(chip_top, chip_h, chip_size), rung["confidence_label"],
                    chip_size, 700, T[f"on_{role}"]))
    return "\n".join(out)


# --------------------------------------------------------------- headline

def headline_svg(W: int, H: int, ground: str, caption: dict, report: dict):
    """The left-aligned headline (Manrope 800) with its accent spans, the
    optional kicker above it and subline below. Returns (svg, text bottom)."""
    k = W / 1080
    size = round(W * HEAD_W)
    track = -0.02 * size
    x = MARGIN * k
    max_w = W - 2 * x
    lines = caption["headline"]
    widest = max(text_width(line, size, 800, track) for line in lines)
    if widest > max_w:
        size = math.floor(size * max_w / widest)
        track = -0.02 * size
        if size < W * HEAD_MIN_W:
            raise RenderError(f"{report['id']}: the headline only fits at {size} px "
                              f"({size / W:.3f} W, floor {HEAD_MIN_W} W); rewrite the line rather than shrink it")
    report["headline_px"] = size
    report["widest_line_px"] = round(max(text_width(line, size, 800, track) for line in lines))
    colours = GROUND_TEXT[ground]
    if caption["accent"] and not colours["accent"]:
        raise RenderError(f"{report['id']}: a {ground} ground has no accent colour; drop the caption's accent")
    first = FIRST_BASELINE * k
    out, boxes = [], []
    if caption.get("kicker"):
        ks = round(W * KICKER_W)
        kb = first - size * KICKER_RISE
        out.append(text(x, kb, caption["kicker"], ks, 700, colours["kicker"]))
        boxes.append(("kicker", colours["kicker"], (x, kb - ks * 0.76, text_width(caption["kicker"], ks, 700), ks)))
    step = size * LEAD
    for i, line in enumerate(lines):
        y = first + i * step
        spans, cursor = [], 0
        marks = sorted((line.find(a), a) for a in caption["accent"] if a in line)
        for at, accent in marks:
            if at < cursor:
                continue
            if at > cursor:
                spans.append((line[cursor:at], colours["headline"]))
            spans.append((accent, colours["accent"]))
            cursor = at + len(accent)
        if cursor < len(line):
            spans.append((line[cursor:], colours["headline"]))
        tspans, prefix = [], ""
        for chunk, colour in spans:
            cw = text_width(chunk, size, 800, track)
            px = x + text_width(prefix, size, 800, track) + (track if prefix else 0)
            boxes.append(("accent" if colour != colours["headline"] else "headline", colour,
                          (px, y - size * 0.74, cw, size * 0.98)))
            prefix += chunk
            tspans.append(f'<tspan fill="{colour}">{escape(chunk)}</tspan>')
        out.append(f'<text x="{f1(x)}" y="{f1(y)}" font-family="Manrope" font-size="{size}" font-weight="800" '
                   f'letter-spacing="{track:.2f}" xml:space="preserve">{"".join(tspans)}</text>')
    bottom = first + (len(lines) - 1) * step + size * 0.24
    if caption.get("subline"):
        ss = round(W * SUBLINE_W)
        sb = bottom + 0.035 * W + ss
        out.append(text(x, sb, caption["subline"], ss, 500, colours["headline"]))
        boxes.append(("subline", colours["headline"], (x, sb - ss * 0.76, text_width(caption["subline"], ss, 500), ss)))
        bottom = sb + ss * 0.3
    report["contrast"] = {}
    for name, colour, box in boxes:
        c = worst_contrast(ground, W, H, box, colour)
        report["contrast"][name] = min(c, report["contrast"].get(name, 99))
        if c < MIN_CONTRAST:
            raise RenderError(f"{report['id']}: the {name} is {c}:1 against its ground; it needs {MIN_CONTRAST}:1")
    return "\n".join(out), bottom, (len(lines) - 2) * step


# ------------------------------------------------------------------ panel

def compose(panel: dict, target: str, size: dict, caption: dict, captures: dict[str, Capture],
            numbers: Numbers, values: dict) -> tuple[str, dict]:
    W, H = size["width"], size["height"]
    k = W / 1080
    ground, T = panel["ground"], THEMES[panel["theme"]]
    report = {"id": panel["id"], "target": target}
    head, text_bottom, extra_lines = headline_svg(W, H, ground, caption, report)
    card_x = CARD_X * k
    card_w = W - 2 * card_x
    card_y = CARD_Y * k + max(0.0, extra_lines)
    if caption.get("subline"):
        card_y = max(card_y, text_bottom + 40 * k)
    max_h = H - card_y - CARD_BOTTOM * k
    pieces = build_stack(panel, target, captures, values, card_w, k)
    used = sum(p.height for p in pieces)
    card_h = min(max_h, used)
    if panel.get("valign") == "center" and card_h < max_h:
        card_y += (max_h - card_h) / 2
    fade = used > max_h or panel.get("fade") == "always"
    empty = H - CARD_BOTTOM * k - (card_y + card_h)
    report["card"] = [round(card_x), round(card_y), round(card_w), round(card_h)]
    if empty > MAX_EMPTY * k:
        report["empty_px_below_card"] = round(empty)

    clip_defs, inner, overlay = [], [], []
    y = card_y
    for i, p in enumerate(pieces):
        if isinstance(p, ImagePiece):
            cid = f"p{i}"
            clip_defs.append(f'<clipPath id="{cid}">{rect(card_x, y, card_w, p.height + 0.6, "#000")}</clipPath>')
            href = escape(p.capture.path.as_uri(), {'"': "&quot;"})
            inner.append(f'<g clip-path="url(#{cid})"><image x="{f1(card_x - p.x0 * p.scale)}" '
                         f'y="{f1(y - p.y0 * p.scale)}" width="{f1(p.capture.width * p.scale)}" '
                         f'height="{f1(p.capture.height * p.scale)}" preserveAspectRatio="none" '
                         f'xlink:href="{href}"/></g>')
            for d0, d1 in p.dims:
                inner.append(rect(card_x, y + (d0 - p.y0) * p.scale, card_w, (d1 - d0) * p.scale, T["bg"],
                                  0, f' fill-opacity="{DIM_OPACITY}"'))
        elif isinstance(p, LiftPiece):
            bx, by, bw, bh = p.box
            lx, lw, lh = card_x - OVERHANG * k, card_w + 2 * OVERHANG * k, bh * p.scale
            sx = card_x + bx * p.scale
            cid = f"p{i}"
            fill = p.fill or T["container"]
            clip_defs.append(f'<clipPath id="{cid}">{rect(sx, y, bw * p.scale, lh, "#000", p.radius)}</clipPath>')
            href = escape(p.capture.path.as_uri(), {'"': "&quot;"})
            overlay.append(f'<g filter="url(#lift)">{rect(lx, y, lw, lh, fill, p.radius)}</g>')
            overlay.append(f'<g clip-path="url(#{cid})"><image x="{f1(card_x)}" y="{f1(y - by * p.scale)}" '
                           f'width="{f1(p.capture.width * p.scale)}" height="{f1(p.capture.height * p.scale)}" '
                           f'preserveAspectRatio="none" xlink:href="{href}"/></g>')
        elif isinstance(p, CalloutPiece):
            cx, cw = card_x - OVERHANG * k, card_w + 2 * OVERHANG * k
            top = y + p.margin
            mag = panel["callout"]["scale"]
            if p.kind == "split":
                overlay.append(split_callout(p, top, cx, cw, mag, numbers, T))
            else:
                fill = p.fill or T["bg"]
                overlay.append(predictor_callout(p, top, cx, cw, mag, numbers, T, fill))
            y += p.height + 2 * p.margin
            continue
        y += p.height

    rad = CARD_RADIUS * k
    edge = CARD_EDGE[ground]
    stroke = f' stroke="{edge[0]}" stroke-opacity="{edge[1]}" stroke-width="{f1(2 * k)}"' if edge else ""
    card = [f'<clipPath id="card">{rect(card_x, card_y, card_w, card_h, "#000", rad)}</clipPath>',
            f'<g filter="url(#lift)">{rect(card_x, card_y, card_w, card_h, T["bg"], rad, stroke)}</g>',
            f'<g clip-path="url(#card)">{"".join(inner)}']
    if fade:
        fh = FADE * k
        card.append(f'<linearGradient id="fade" x1="0" y1="{f1(card_y + card_h - fh)}" x2="0" '
                    f'y2="{f1(card_y + card_h)}" gradientUnits="userSpaceOnUse">'
                    f'<stop offset="0" stop-color="{T["bg"]}" stop-opacity="0"/>'
                    f'<stop offset="0.85" stop-color="{T["bg"]}" stop-opacity="1"/></linearGradient>')
        card.append(rect(card_x, card_y + card_h - fh, card_w, fh, "url(#fade)"))
    card.append("</g>")
    if edge:
        card.append(rect(card_x, card_y, card_w, card_h, "none", rad, stroke))

    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           f'width="{W}" height="{H}" viewBox="0 0 {W} {H}">\n'
           f'<defs>{ground_defs(ground, W, H)}{"".join(clip_defs)}</defs>\n'
           f'{rect(0, 0, W, H, "url(#g1)")}{rect(0, 0, W, H, "url(#g2)")}\n'
           + "\n".join(card) + "\n" + "\n".join(overlay) + "\n" + head + "\n</svg>\n")
    return svg, report


# --------------------------------------------------------------- the run

def load_config() -> dict:
    return json.loads((HERE / "panels.json").read_text())


def panel_sets(config: dict, targets: list[str]):
    """(target, output dir name, [panel, ...]) for the listing and each variant."""
    by_id = {p["id"]: p for p in config["panels"] + config.get("alternates", [])}
    for target in targets:
        yield target, target, config["panels"]
        for variant in config.get("variants", []):
            if target in variant["targets"]:
                swapped = [by_id[variant["replace"].get(p["id"], p["id"])] for p in config["panels"]]
                yield target, f"{target}-{variant['name']}", swapped


def prepare(config: dict, captions: dict, numbers: Numbers, target: str, panels: list[dict]):
    """Resolve and check every caption of a panel set before anything renders."""
    problems = []
    values = numbers.placeholders()
    resolved = {}
    for panel in panels:
        for claim in panel.get("claims", []) + config.get("claims", []):
            reason = numbers.check(claim)
            if reason:
                problems.append(f"{panel['id']} ({target}): {reason}")
        caption = captions.get(panel["id"])
        if caption is None:
            problems.append(f"no caption for panel {panel['id']!r}")
            continue
        try:
            resolved[panel["id"]] = resolve_caption(panel["id"], caption, panel.get("numbers", []), values)
        except DataError as e:
            problems.append(str(e))
    return resolved, values, problems


def inkscape(svg: Path, png: Path, size: dict):
    subprocess.run(
        ["inkscape", str(svg), "--export-type=png", f"--export-filename={png}",
         f"--export-width={size['width']}", f"--export-height={size['height']}",
         "--export-background=#000000", "--export-background-opacity=1", "--export-png-color-mode=RGB_8"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    w, h, depth, colour = png_header(png)
    if (w, h) != (size["width"], size["height"]) or depth != 8 or colour != 2:
        raise RenderError(f"{png} is {w}x{h}, bit depth {depth}, colour type {colour}; "
                          f"expected {size['width']}x{size['height']} 8-bit RGB (type 2)")


def parse_captures(items: list[str]) -> dict[str, Path]:
    out = {}
    for item in items:
        target, sep, path = item.partition("=")
        if not sep:
            raise RenderError(f"--captures takes TARGET=DIR, got {item!r}")
        out[target] = Path(path)
    return out


def resolve_dirs(config: dict, given: dict[str, Path], targets: list[str], fallback_ok: bool) -> dict[str, Path]:
    dirs = {}
    for target in targets:
        if target in given:
            dirs[target] = given[target]
            continue
        source = config["targets"][target].get("fallback_from")
        if fallback_ok and source and source in given:
            print(f"::warning::{target} is rendered from the {source} captures (--appstore-from-android). "
                  f"Those are {config['targets'][source]['platform']} screens; do not upload this set "
                  f"to App Store Connect.", file=sys.stderr)
            dirs[target] = given[source]
            continue
        raise RenderError(f"no captures for {target} ({config['targets'][target]['platform']}): pass "
                          f"--captures {target}=DIR" + (" or, during the transition only, --appstore-from-android"
                                                         if source else ""))
    return dirs


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--captures", action="append", default=[], metavar="TARGET=DIR",
                    help="a target's capture directory (PNGs, bounds.json, numbers.json)")
    ap.add_argument("--out", required=True, type=Path, help="directory to write panels into")
    ap.add_argument("--locale", action="append", help="only these locales (default: every captions/*.json)")
    ap.add_argument("--target", action="append", help="only these targets (default: all)")
    ap.add_argument("--appstore-from-android", action="store_true",
                    help="transition only: render appstore-6.9 from the play-phone captures, with a warning")
    ap.add_argument("--keep-svg", action="store_true", help="keep each panel's SVG beside its PNG")
    args = ap.parse_args(argv)

    config = load_config()
    targets = args.target or list(config["targets"])
    locales = args.locale or sorted(p.stem for p in (HERE / "captions").glob("*.json"))
    try:
        unknown = [t for t in targets if t not in config["targets"]]
        if unknown:
            raise RenderError(f"unknown target(s) {unknown}")
        dirs = resolve_dirs(config, parse_captures(args.captures), targets, args.appstore_from_android)
        loaded = {t: load_capture_dir(d) for t, d in dirs.items()}
    except RenderError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    if shutil.which("inkscape") is None:
        print("error: 'inkscape' not on PATH", file=sys.stderr)
        return 1

    jobs, problems = [], []
    for locale in locales:
        source = HERE / "captions" / f"{locale}.json"
        if not source.is_file():
            problems.append(f"no captions for locale {locale!r} ({source})")
            continue
        captions = json.loads(source.read_text())
        for target, out_name, panels in panel_sets(config, targets):
            captures, numbers = loaded[target]
            resolved, values, found = prepare(config, captions, numbers, target, panels)
            problems += [f"{locale}: {p}" for p in found]
            for index, panel in enumerate(panels, start=1):
                if panel["id"] in resolved:
                    jobs.append((locale, target, out_name, index, panel, resolved[panel["id"]], values))
    svgs = []
    for locale, target, out_name, index, panel, caption, values in jobs:
        captures, numbers = loaded[target]
        try:
            svg, report = compose(panel, target, config["targets"][target], caption, captures, numbers, values)
        except RenderError as e:
            problems.append(f"{locale}/{out_name}: {e}")
            continue
        svgs.append((locale, target, out_name, index, panel, svg, report))
    if problems:
        for p in dict.fromkeys(problems):
            print(f"error: {p}", file=sys.stderr)
        return 1

    reports = []
    try:
        with tempfile.TemporaryDirectory() as work:
            for locale, target, out_name, index, panel, svg, report in svgs:
                dest = args.out / locale / out_name
                dest.mkdir(parents=True, exist_ok=True)
                stem = f"{index:02d}-{panel['id']}"
                svg_path = (dest if args.keep_svg else Path(work)) / f"{stem}.svg"
                svg_path.write_text(svg)
                png = dest / f"{stem}.png"
                inkscape(svg_path, png, config["targets"][target])
                report["file"] = str(png.relative_to(args.out))
                reports.append(report)
                note = f" ({report['empty_px_below_card']} px of bare ground under the card)" \
                    if "empty_px_below_card" in report else ""
                print(f"wrote {png}{note}")
    except RenderError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    (args.out / "report.json").write_text(json.dumps(reports, indent=1) + "\n")
    print(f"{len(reports)} panels")
    return 0


if __name__ == "__main__":
    sys.exit(main())
