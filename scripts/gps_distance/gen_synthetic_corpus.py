"""Writes the one SYNTHETIC entry of the GPS ground-truth corpus.

Six laps of lane 1 of a standard 400 m track at a steady 4:20/km, recorded
the way an iPhone at full accuracy reports it: one fix a second, AR(1)
correlated position error (sigma 3 m, lag-1 correlation 0.95 -- the
Ranacher 2015 "C"), a stated accuracy near 4 m, Doppler speed and bearing
with small white noise, and one 25 m multipath spike the phone still reports
as accurate. Deterministic: a fixed-seed splitmix64, no `random` module, so
the bytes never depend on the Python version.

It exists so the replay harness has something to run in CI before the
owner's real tracks land. It is not evidence about real GPS -- see
fixtures/gps_corpus/README.md.

Usage:
  python3 -I scripts/gps_distance/gen_synthetic_corpus.py fixtures/gps_corpus
"""
import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone

EARTH_RADIUS_M = 6371008.8
STRAIGHT_M = 84.39
LANE1_RADIUS_M = 36.80          # 36.50 m kerb radius + the 0.30 m measurement line
LAP_M = 2 * STRAIGHT_M + 2 * math.pi * LANE1_RADIUS_M   # 400.00 m
LAPS = 6
DURATION_S = 624                # 2400 m at 4:20/km
ORIGIN_LAT, ORIGIN_LNG = 45.0, -93.0
SEED = 1090
NAME = "track_400m_lane1_x6.synthetic"


class SplitMix64:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFFFFFFFFFF

    def uniform(self):
        self.s = (self.s + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        z ^= z >> 31
        return ((z >> 11) + 0.5) / float(1 << 53)

    def gauss(self):
        u1, u2 = self.uniform(), self.uniform()
        return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)


def lane1(s):
    """Position (x, y) metres and heading (deg, clockwise from north) at
    distance s along lane 1, run anticlockwise starting at the 100 m start."""
    s %= LAP_M
    r, h = LANE1_RADIUS_M, STRAIGHT_M / 2
    if s < STRAIGHT_M:                                   # home straight, heading north
        return r, -h + s, 0.0
    s -= STRAIGHT_M
    if s < math.pi * r:                                  # top bend, centre (0, h)
        a = s / r
        return r * math.cos(a), h + r * math.sin(a), (360.0 - math.degrees(a)) % 360.0
    s -= math.pi * r
    if s < STRAIGHT_M:                                   # back straight, heading south
        return -r, h - s, 180.0
    s -= STRAIGHT_M
    a = s / r                                            # bottom bend, centre (0, -h)
    return -r * math.cos(a), -h - r * math.sin(a), (180.0 - math.degrees(a)) % 360.0


def to_lat_lng(x, y):
    lat = ORIGIN_LAT + math.degrees(y / EARTH_RADIUS_M)
    lng = ORIGIN_LNG + math.degrees(x / (EARTH_RADIUS_M * math.cos(math.radians(ORIGIN_LAT))))
    return lat, lng


def build():
    rng = SplitMix64(SEED)
    speed = LAPS * LAP_M / DURATION_S
    phi, sigma = 0.95, 3.0
    innov = sigma * math.sqrt(1.0 - phi * phi)
    ex, ey = sigma * rng.gauss(), sigma * rng.gauss()
    t0 = datetime(2026, 10, 1, 7, 0, 0, tzinfo=timezone.utc)
    out = []
    for k in range(DURATION_S + 1):
        if k > 0:
            ex = phi * ex + innov * rng.gauss()
            ey = phi * ey + innov * rng.gauss()
        x, y, heading = lane1(speed * k)
        mx, my = x + ex, y + ey
        if k == 300:
            mx += 25.0
        lat, lng = to_lat_lng(mx, my)
        out.append({
            "lat": round(lat, 8),
            "lng": round(lng, 8),
            "ts": (t0 + timedelta(seconds=k)).isoformat().replace("+00:00", "Z"),
            "accuracyMetres": round(4.0 + 0.5 * rng.gauss(), 1),
            "speedMps": round(max(0.0, speed + 0.15 * rng.gauss()), 3),
            "speedAccuracyMps": 0.3,
            "bearingDeg": round((heading + 3.0 * rng.gauss()) % 360.0, 1),
        })
    return out


def manifest():
    return {
        "id": "track-400m-lane1-x6-synthetic",
        "synthetic": True,
        "track_file": NAME + ".json",
        "format": "threkir_json",
        "known_distance_m": round(LAPS * LAP_M, 2),
        "distance_source": "synthetic: 6 x the IAAF lane-1 measurement line (2 x 84.39 m + 2 x pi x 36.80 m)",
        "course_type": "track",
        "device": "synthetic (gen_synthetic_corpus.py, seed %d)" % SEED,
        "platform": "synthetic",
        "activity_type": "run",
        "error_budget_pct": 3.0,
        "notes": "Generated, not recorded. 1 Hz, AR(1) position error sigma 3 m / lag-1 0.95, "
                 "Doppler sigma 0.15 m/s, one 25 m multipath spike at t=300 s. Proves the harness "
                 "runs; says nothing about real GPS.",
    }


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    with open(os.path.join(d, NAME + ".json"), "w") as f:
        json.dump(build(), f, separators=(",", ":"))
        f.write("\n")
    with open(os.path.join(d, NAME + ".manifest.json"), "w") as f:
        json.dump(manifest(), f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
