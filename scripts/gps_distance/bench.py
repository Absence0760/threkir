"""Synthetic noise bench for the GPS distance estimator (spec v1.2).

Prints the error against the true path length for the old hop-sum, the
forward filter (live screens) and the smoother (saved / recomputed figure),
averaged over SEEDS seeds, worst seed in brackets. Synthetic only — the
ground-truth corpus (fixtures/gps_corpus/) is what validates the constants.

  python3 -I scripts/gps_distance/bench.py
"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference as ref

SEEDS = 5
LAT0, LNG0 = 40.0, -75.0
MLAT = 111195.0


def course(T, speed_at, turn_every, turn_deg, stops=()):
    """True path at 1 s resolution: positions (m), velocity vector, cumulative length."""
    x = y = h = 0.0
    out, true = [], 0.0
    for t in range(T):
        stopped = any(a <= t < a + l for a, l in stops)
        s = 0.0 if stopped else speed_at(t)
        if t and t % turn_every == 0:
            h += math.radians(turn_deg if (t // turn_every) % 2 else -turn_deg * 0.8)
        vx, vy = s * math.sin(h), s * math.cos(h)
        if t:
            x += vx; y += vy; true += s
        out.append((x, y, vx, vy))
    return out, true


def run(cfg, seed, est_cls=ref.GpsDistanceEstimator, smoother=ref.smooth_distance):
    r = random.Random(seed)
    T = cfg.get("T", 1850)
    v = cfg.get("v", 2.68)
    speed_at = cfg.get("speed_at", lambda t: v)
    pts, true = course(T, speed_at, cfg.get("turn_every", 90), cfg.get("turn_deg", 90), cfg.get("stops", ()))
    sigma, rho, white = cfg.get("sigma", 3.0), cfg.get("rho", 0.9), cfg.get("white", 1.0)
    stated = cfg.get("stated", sigma * 1.2)
    every = cfg.get("every", 1)
    doppler = cfg.get("doppler", True)
    dsig = cfg.get("dsig", 0.2)
    dstated = cfg.get("dstated", 0.4)
    bias = cfg.get("bias", 0.0)
    spikes = cfg.get("spikes", 0.0)
    k = math.sqrt(1 - rho * rho)
    nx = ny = 0.0
    mlng = MLAT * math.cos(math.radians(LAT0))
    events, anchor, naive = [], None, 0.0
    for t, (x, y, vx, vy) in enumerate(pts):
        nx = rho * nx + k * r.gauss(0, sigma)
        ny = rho * ny + k * r.gauss(0, sigma)
        X, Y = x + nx + r.gauss(0, white), y + ny + r.gauss(0, white)
        if spikes and r.random() < spikes:
            a = r.uniform(0, 2 * math.pi); m = r.uniform(25, 60)
            X += m * math.sin(a); Y += m * math.cos(a)
        if t % every:
            continue
        fix = {"type": "fix", "t": float(t), "lat": LAT0 + Y / MLAT, "lng": LNG0 + X / mlng,
               "acc": stated, "speed": None, "speedAcc": None, "bearing": None}
        if doppler:
            dvx, dvy = vx + r.gauss(0, dsig), vy + r.gauss(0, dsig)
            s = math.hypot(dvx, dvy) + bias
            fix["speed"], fix["speedAcc"] = max(0.0, s), dstated
            fix["bearing"] = math.degrees(math.atan2(dvx, dvy)) % 360 if math.hypot(vx, vy) > 0 else None
        events.append(fix)
        if anchor is None:
            anchor = (X, Y)
        else:
            d = math.hypot(X - anchor[0], Y - anchor[1])
            if 3 < d < 100:
                naive += d; anchor = (X, Y)
    events.append({"type": "finish", "t": float(T)})
    e = est_cls(cfg.get("max_speed", 10.0), float(every))
    for ev in events:
        if ev["type"] == "fix":
            e.add_fix(ev["t"], ev["lat"], ev["lng"], ev["acc"], ev["speed"], ev["speedAcc"], ev["bearing"])
        else:
            e.finish(ev["t"])
    sm = smoother(events, cfg.get("max_speed", 10.0), float(every)) if smoother else None
    return true, naive, e.distance_m, (sm["distance_m"] if sm else None)


FOREST = {"v": 2.2, "turn_every": 25, "turn_deg": 90, "sigma": 6.0, "rho": 0.97, "white": 2.0,
          "dsig": 0.35, "dstated": 0.5}
SWITCHBACKS = dict(FOREST, turn_every=12, turn_deg=150)

SCENARIOS = [
    ("sigma 3 m, rho 0.9", {}),
    ("sigma 3 m, rho 0.9, two stops", {"stops": ((300, 120), (1200, 90))}),
    ("sigma 4 m, rho 0.95, two stops", {"sigma": 4.0, "rho": 0.95, "white": 1.5, "stops": ((300, 120), (1200, 90))}),
    ("sigma 3 m, rho 0.9, position-only", {"doppler": False}),
    ("sigma 3 m, rho 0.9, two stops, position-only", {"doppler": False, "stops": ((300, 120), (1200, 90))}),
    ("sigma 4 m, rho 0.95, two stops, position-only", {"doppler": False, "sigma": 4.0, "rho": 0.95, "white": 1.5,
                                                      "stops": ((300, 120), (1200, 90))}),
    ("Android 5 s fixes, sigma 4 m", {"every": 5, "sigma": 4.0, "rho": 0.95}),
    ("multipath spikes 3%, stated 4 m", {"spikes": 0.03}),
    ("multipath spikes 3%, position-only", {"spikes": 0.03, "doppler": False}),
    ("optimistic accuracy (true 8 m, stated 3 m), position-only", {"sigma": 8.0, "rho": 0.6, "stated": 3.0,
                                                                   "doppler": False}),
    ("Doppler biased +0.5 m/s", {"bias": 0.5}),
    ("slow walk 1.0 m/s, Doppler sigma 0.3 honest", {"v": 1.0, "dsig": 0.3, "dstated": 0.3, "max_speed": 5.0}),
    ("slow walk 1.0 m/s, Doppler sigma 0.15, stated 0.5", {"v": 1.0, "dsig": 0.15, "dstated": 0.5, "max_speed": 5.0}),
    ("pace change 2 <-> 4 m/s every 60 s, position-only", {"doppler": False, "speed_at": lambda t: 2.0 if (t // 60) % 2 else 4.0}),
    ("forest trail: 90 deg turn every 25 s, sigma 6 m, rho 0.97", FOREST),
    ("forest trail, position-only", dict(FOREST, doppler=False)),
    ("canopy switchbacks: 150 deg every 12 s, sigma 6 m, rho 0.97", SWITCHBACKS),
    ("canopy switchbacks, position-only", dict(SWITCHBACKS, doppler=False)),
    ("urban canyon: sigma 8 m, rho 0.98, spikes 5%, turns every 30 s", {"turn_every": 30, "sigma": 8.0, "rho": 0.98,
                                                                       "white": 2.0, "spikes": 0.05, "dsig": 0.4,
                                                                       "dstated": 0.6}),
]


def pct(a, t):
    return 100.0 * (a / t - 1.0)


def summarise(cfg, est_cls=ref.GpsDistanceEstimator, smoother=ref.smooth_distance):
    rows = [run(cfg, s, est_cls, smoother) for s in range(1, SEEDS + 1)]
    cols = []
    for i in (1, 2, 3):
        if rows[0][i] is None:
            cols.append(None)
            continue
        errs = [pct(r[i], r[0]) for r in rows]
        cols.append((sum(errs) / len(errs), max(errs, key=abs)))
    return cols


if __name__ == "__main__":
    print(f"spec v{ref.SPEC_VERSION}, mean of {SEEDS} seeds [worst seed]")
    for name, cfg in SCENARIOS:
        naive, fwd, sm = summarise(cfg)
        print(f"{name:62s} hop-sum {naive[0]:+6.1f}%  forward {fwd[0]:+5.1f}% [{fwd[1]:+5.1f}]  "
              f"smoothed {sm[0]:+5.1f}% [{sm[1]:+5.1f}]")
