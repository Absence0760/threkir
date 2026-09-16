"""Trace topographic contour lines of `terrain.height()` into an SVG.

The flat companion to the Blender render: the same ground seen from above as a
map would draw it, with every fifth line heavier as an index contour. The web
uses it as a CSS mask, so the strokes carry shape only and the page supplies
the colour from its own tokens.

    python3 assets/marketing/contours.py [out.svg]

Marching squares, then segments chained into polylines, thinned with
Ramer-Douglas-Peucker, and drawn as midpoint quadratics so the lines read as
surveyed rather than as a staircase of grid cells.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terrain  # noqa: E402

WIDTH, HEIGHT = 1200, 800
COLS, ROWS = 240, 160
# Region of the world drawn, in world units (3:2 like the viewBox).
X0, X1 = -12.0, 12.0
Y0, Y1 = -3.0, 13.0
STEP = 0.16
INDEX_EVERY = 5
# Closed specks shorter than this (px) are noise at any display size.
MIN_LENGTH = 24.0
EPSILON = 1.1


def sample():
    grid = []
    for r in range(ROWS + 1):
        y = Y1 - (Y1 - Y0) * r / ROWS
        grid.append([terrain.height(X0 + (X1 - X0) * c / COLS, y) for c in range(COLS + 1)])
    return grid


def point(r, c):
    return (c * WIDTH / COLS, r * HEIGHT / ROWS)


def trace(grid, level):
    """Segments for one level, each endpoint keyed by the grid edge it sits on."""
    segs = []

    def edge_point(a, b):
        (ra, ca), (rb, cb) = a, b
        va, vb = grid[ra][ca], grid[rb][cb]
        t = (level - va) / (vb - va)
        pa, pb = point(ra, ca), point(rb, cb)
        key = (min(a, b), max(a, b))
        return key, (pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t)

    for r in range(ROWS):
        for c in range(COLS):
            corners = [(r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)]
            above = [grid[rr][cc] >= level for rr, cc in corners]
            crossings = []
            for i in range(4):
                a, b = corners[i], corners[(i + 1) % 4]
                if above[i] != above[(i + 1) % 4]:
                    crossings.append(edge_point(a, b))
            if len(crossings) == 2:
                segs.append((crossings[0], crossings[1]))
            elif len(crossings) == 4:
                # Saddle: resolve by the cell's mean, consistently per level.
                centre = sum(grid[rr][cc] for rr, cc in corners) / 4
                if (centre >= level) == above[0]:
                    segs.append((crossings[0], crossings[3]))
                    segs.append((crossings[1], crossings[2]))
                else:
                    segs.append((crossings[0], crossings[1]))
                    segs.append((crossings[2], crossings[3]))
    return segs


def chain(segs):
    by_key = {}
    for i, (a, b) in enumerate(segs):
        by_key.setdefault(a[0], []).append(i)
        by_key.setdefault(b[0], []).append(i)
    used = [False] * len(segs)
    lines = []
    for start in range(len(segs)):
        if used[start]:
            continue
        used[start] = True
        a, b = segs[start]
        line = [a, b]
        for forward in (True, False):
            while True:
                tip = line[-1] if forward else line[0]
                nxt = next((i for i in by_key.get(tip[0], []) if not used[i]), None)
                if nxt is None:
                    break
                used[nxt] = True
                p, q = segs[nxt]
                other = q if p[0] == tip[0] else p
                if forward:
                    line.append(other)
                else:
                    line.insert(0, other)
        lines.append([pt for _, pt in line])
    return lines


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    norm = math.hypot(dx, dy) or 1e-9
    worst, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + x1 * y0 - y1 * x0) / norm
        if d > worst:
            worst, idx = d, i
    if worst <= eps:
        return [pts[0], pts[-1]]
    return rdp(pts[: idx + 1], eps)[:-1] + rdp(pts[idx:], eps)


def length(pts):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


def fmt(v):
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def path_d(pts):
    if len(pts) < 3:
        return "M" + " L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)
    d = [f"M{fmt(pts[0][0])} {fmt(pts[0][1])}"]
    for i in range(1, len(pts) - 1):
        (x, y), (nx, ny) = pts[i], pts[i + 1]
        d.append(f"Q{fmt(x)} {fmt(y)} {fmt((x + nx) / 2)} {fmt((y + ny) / 2)}")
    d.append(f"L{fmt(pts[-1][0])} {fmt(pts[-1][1])}")
    return "".join(d)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "out", "topo.svg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    grid = sample()
    lo = min(min(row) for row in grid)
    hi = max(max(row) for row in grid)
    minor, major = [], []
    k = math.ceil(lo / STEP)
    while k * STEP < hi:
        level = k * STEP
        lines = [rdp(line, EPSILON) for line in chain(trace(grid, level))]
        ds = [path_d(line) for line in lines if len(line) >= 2 and length(line) >= MIN_LENGTH]
        (major if k % INDEX_EVERY == 0 else minor).extend(ds)
        k += 1
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" '
        f'width="{WIDTH}" height="{HEIGHT}" fill="none" stroke="#000" stroke-linecap="round" '
        f'stroke-linejoin="round">'
        f'<path stroke-width="1.1" d="{"".join(minor)}"/>'
        f'<path stroke-width="2.2" d="{"".join(major)}"/>'
        "</svg>\n"
    )
    with open(out, "w") as f:
        f.write(svg)
    print(f"wrote {out} ({len(svg) // 1024} KB, {len(minor)} minor + {len(major)} index lines)")


if __name__ == "__main__":
    main()
