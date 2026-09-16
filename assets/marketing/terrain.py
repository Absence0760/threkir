"""Deterministic terrain + route shared by the marketing generators.

One heightfield feeds two outputs, so the 3D render and the flat contour map
describe the same place: `scene.py` (Blender) builds a mesh from `height()` and
threads a glowing tube along `route()`, and `contours.py` (plain Python) traces
iso-lines of the same `height()` into an SVG.

Pure Python with no numpy, because it runs under two interpreters: Blender's
bundled Python and the system python3.
"""
import math
import random

SEED = 1729

# World extents. The hero camera looks along +y from the negative-y edge, so
# the near field is low and rolling and the far field rises into ridges.
X_MIN, X_MAX = -12.0, 12.0
Y_MIN, Y_MAX = -8.0, 16.0


def _permutation(seed):
    rng = random.Random(seed)
    p = list(range(256))
    rng.shuffle(p)
    return p + p


_PERM = _permutation(SEED)
_GRADS = [(math.cos(a), math.sin(a)) for a in (i * math.tau / 16 for i in range(16))]


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def _lerp(a, b, t):
    return a + (b - a) * t


def perlin(x, y):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    xi &= 255
    yi &= 255

    def grad(ix, iy, dx, dy):
        g = _GRADS[_PERM[_PERM[ix] + iy] & 15]
        return g[0] * dx + g[1] * dy

    n00 = grad(xi, yi, xf, yf)
    n10 = grad(xi + 1, yi, xf - 1, yf)
    n01 = grad(xi, yi + 1, xf, yf - 1)
    n11 = grad(xi + 1, yi + 1, xf - 1, yf - 1)
    u, v = _fade(xf), _fade(yf)
    return _lerp(_lerp(n00, n10, u), _lerp(n01, n11, u), v)


def fbm(x, y, octaves=5):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        total += perlin(x * freq, y * freq) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.03
    return total / norm


def _smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def height(x, y):
    # Rolling base everywhere, ridged mountains that grow with distance.
    base = fbm(x * 0.11 + 3.1, y * 0.11 - 7.4) * 1.1
    ridge = 1.0 - abs(fbm(x * 0.07 - 11.0, y * 0.07 + 5.0, octaves=4))
    ridge = ridge * ridge
    far = _smoothstep(1.0, 13.0, y)
    h = base + ridge * (0.6 + 3.4 * far)
    # A valley floor under the route's first half keeps the line in view
    # instead of disappearing behind the nearest hill.
    valley = math.exp(-((x + 0.8 * math.sin(y * 0.25)) ** 2) / 18.0) * (1.0 - far)
    return h - valley * 0.9


# Control points in world XY, near to far, chosen against the hero camera.
# The landing page's product shot covers the middle of that frame, so the
# line swings out to the frame's edges where it stays visible: in low on the
# left, a wide bend on the right, then switchbacks along the far ridges that
# show above the shot.
_ROUTE_CTRL = [
    (-3.3, -6.0), (-1.4, -5.4), (1.8, -4.8), (4.5, -3.6),
    (5.2, -1.6), (3.0, 0.6), (-0.5, 1.8), (-4.0, 3.0),
    (-6.5, 5.4), (-5.5, 8.0), (-1.5, 9.6), (3.5, 10.8), (7.0, 12.6),
]


def _catmull_rom(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(
        0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
               + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
        for i in range(2)
    )


def route(samples_per_span=24, lift=0.06):
    """The route as (x, y, z) points resting just above the surface."""
    pts = [_ROUTE_CTRL[0]] + _ROUTE_CTRL + [_ROUTE_CTRL[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        for s in range(samples_per_span):
            x, y = _catmull_rom(pts[i - 1], pts[i], pts[i + 1], pts[i + 2], s / samples_per_span)
            out.append((x, y, height(x, y) + lift))
    x, y = _ROUTE_CTRL[-1]
    out.append((x, y, height(x, y) + lift))
    return out
