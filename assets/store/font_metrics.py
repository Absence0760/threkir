"""Advance widths for the repo's Manrope TTFs, read with the standard library.

The renderer measures every headline line with the real font before it lays a
panel out, so a line too wide for the panel fails the build instead of running
off the edge. Kerning is ignored, so widths run a touch wide, which is the
safe side for fitting.
"""
from __future__ import annotations

import struct
from pathlib import Path

FONT_DIR = Path(__file__).resolve().parents[2] / "packages" / "ui_kit" / "fonts"
WEIGHT_FILES = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}


class Metrics:
    def __init__(self, path: Path):
        d = path.read_bytes()
        tables = {}
        for i in range(struct.unpack(">H", d[4:6])[0]):
            tag, _, off, _ = struct.unpack(">4sIII", d[12 + 16 * i:28 + 16 * i])
            tables[tag.decode("latin-1")] = off
        self.upem = struct.unpack(">H", d[tables["head"] + 18:tables["head"] + 20])[0]
        long_metrics = struct.unpack(">H", d[tables["hhea"] + 34:tables["hhea"] + 36])[0]
        h = tables["hmtx"]
        self.advances = [struct.unpack(">H", d[h + 4 * i:h + 4 * i + 2])[0] for i in range(long_metrics)]
        self.cmap = _cmap(d, tables["cmap"])

    def width(self, text: str, size: float, tracking: float = 0.0) -> float:
        units = 0
        for ch in text:
            glyph = self.cmap.get(ord(ch), 0)
            units += self.advances[min(glyph, len(self.advances) - 1)]
        return units / self.upem * size + tracking * max(len(text) - 1, 0)


def _cmap(d: bytes, c: int) -> dict[int, int]:
    best: dict[int, int] = {}
    for i in range(struct.unpack(">H", d[c + 2:c + 4])[0]):
        pid, _, off = struct.unpack(">HHI", d[c + 4 + 8 * i:c + 12 + 8 * i])
        s = c + off
        fmt = struct.unpack(">H", d[s:s + 2])[0]
        if fmt == 12:
            out = {}
            for g in range(struct.unpack(">I", d[s + 12:s + 16])[0]):
                start, end, gid = struct.unpack(">III", d[s + 16 + 12 * g:s + 28 + 12 * g])
                for cp in range(start, end + 1):
                    out[cp] = gid + cp - start
            return out
        if fmt == 4 and pid in (0, 3) and not best:
            seg = struct.unpack(">H", d[s + 6:s + 8])[0] // 2
            ends = struct.unpack(f">{seg}H", d[s + 14:s + 14 + 2 * seg])
            p = s + 16 + 2 * seg
            starts = struct.unpack(f">{seg}H", d[p:p + 2 * seg])
            deltas = struct.unpack(f">{seg}h", d[p + 2 * seg:p + 4 * seg])
            ro_at = p + 4 * seg
            offsets = struct.unpack(f">{seg}H", d[ro_at:ro_at + 2 * seg])
            for k in range(seg):
                for cp in range(starts[k], ends[k] + 1):
                    if cp == 0xFFFF:
                        continue
                    if offsets[k] == 0:
                        gid = (cp + deltas[k]) & 0xFFFF
                    else:
                        a = ro_at + 2 * k + offsets[k] + 2 * (cp - starts[k])
                        gid = struct.unpack(">H", d[a:a + 2])[0]
                        gid = (gid + deltas[k]) & 0xFFFF if gid else 0
                    best[cp] = gid
    return best


_CACHE: dict[int, Metrics] = {}


def metrics(weight: int) -> Metrics:
    w = min(WEIGHT_FILES, key=lambda k: abs(k - weight))
    if w not in _CACHE:
        _CACHE[w] = Metrics(FONT_DIR / f"Manrope-{WEIGHT_FILES[w]}.ttf")
    return _CACHE[w]


def text_width(text: str, size: float, weight: int, tracking: float = 0.0) -> float:
    return metrics(weight).width(text, size, tracking)
