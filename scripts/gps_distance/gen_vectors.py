import json, math, random, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import reference as ref
from reference import GpsDistanceEstimator

LAT0, LNG0 = 40.0, -75.0
MLAT = 111195.0
MLNG = MLAT * math.cos(math.radians(LAT0))

def walk(T, v, seed, sigma=3.0, rho=0.9, doppler=True, stops=(), drop=(), steps=False, cadence=2.8, gaps_steps=True, every=1):
    r = random.Random(seed)
    x = y = h = 0.0; nx = ny = 0.0; k = math.sqrt(1 - rho * rho); ev = []; cnt = 0; stepacc = 0.0
    for t in range(T):
        stopped = any(a <= t < a + l for a, l in stops)
        s = 0.0 if stopped else v
        if t % 40 == 0 and t: h += math.radians(70 if (t // 40) % 2 else -50)
        x += s * math.sin(h); y += s * math.cos(h)
        nx = rho * nx + k * r.gauss(0, sigma); ny = rho * ny + k * r.gauss(0, sigma)
        if steps and s > 0:
            stepacc += cadence
        if steps:
            cnt = int(stepacc)
            ev.append({"type": "steps", "t": float(t) + 0.5, "count": cnt})
        if any(a <= t < a + l for a, l in drop) or t % every:
            continue
        fix = {"type": "fix", "t": float(t),
               "lat": round(LAT0 + (y + ny) / MLAT, 9), "lng": round(LNG0 + (x + nx) / MLNG, 9),
               "acc": round(sigma * 1.2 + abs(r.gauss(0, 1)), 2),
               "speed": None, "speedAcc": None, "bearing": None}
        if doppler:
            fix["speed"] = round(abs(s + r.gauss(0, 0.15)), 3)
            fix["speedAcc"] = round(0.3 + abs(r.gauss(0, 0.1)), 3)
            fix["bearing"] = round((math.degrees(h) + r.gauss(0, 8)) % 360, 2) if s > 0 else None
        ev.append(fix)
    ev.sort(key=lambda e: e["t"])
    ev.append({"type": "finish", "t": float(T)})
    return ev

def evaluate(events, max_speed=10.0, interval=1.0, stride=None):
    e = GpsDistanceEstimator(max_speed, interval, stride)
    out = []
    for x in events:
        if x["type"] == "fix":
            e.add_fix(x["t"], x["lat"], x["lng"], x["acc"], x["speed"], x["speedAcc"], x["bearing"])
        elif x["type"] == "steps":
            e.add_steps(x["t"], x["count"])
        else:
            e.finish(x["t"])
        out.append(round(e.distance_m, 6))
    return e, out

scen = []
def add(name, desc, events, max_speed=10.0, interval=1.0, stride=None):
    e, out = evaluate(events, max_speed, interval, stride)
    scen.append({"name": name, "description": desc, "maxSpeedMps": max_speed,
                 "expectedIntervalS": interval, "initialStrideM": stride, "events": events,
                 "expected": {"distanceAfterEachEventM": out,
                              "gpsDistanceM": round(e.gps_distance_m, 6),
                              "stepDistanceM": round(e.step_distance_m, 6),
                              "strideM": None if e.stride_m is None else round(e.stride_m, 6)}})

add("doppler_run", "120 s run at 2.68 m/s with Doppler speed + bearing; true distance 318.9 m", walk(120, 2.68, 1))
add("position_only_run", "120 s run with no Doppler (legacy track); true distance 318.9 m", walk(120, 2.68, 2, doppler=False))
add("stationary_doppler", "90 s standing still with jitter; Doppler ~0.15 m/s; expect ~0", walk(90, 0.0, 3))
add("stationary_position_only", "90 s standing still, no Doppler; expect ~0", walk(90, 0.0, 4, doppler=False))
add("stop_and_go", "red-light stop mid-run with Doppler", walk(150, 2.68, 5, stops=((50, 40),)))
add("gap_no_steps", "30 s fix gap mid-run, no pedometer: gap not credited", walk(120, 2.68, 6, drop=((50, 30),)))
add("gap_with_steps", "stride learned over 80 s, then 40 s fix gap filled by steps x stride", walk(160, 2.68, 7, drop=((80, 40),), steps=True))
add("short_gap_with_steps", "6 s fix gap: filter integrates it, buffered steps discarded", walk(120, 2.68, 8, drop=((80, 6),), steps=True))
add("trailing_gap_with_steps", "fixes stop 30 s before finish: steps committed at finish", walk(140, 2.68, 9, drop=((110, 40),), steps=True))
add("walker", "1.3 m/s walk with Doppler", walk(120, 1.3, 10), max_speed=5.0)
add("sparse_15s", "fixes every 15 s (firmware power mode) with Doppler; expectedIntervalS 15 keeps them inside the gap window", walk(300, 2.68, 12, every=15), interval=15.0)
add("sparse_60s_position_only", "fixes every 60 s, no Doppler, expectedIntervalS 60", walk(600, 2.68, 13, doppler=False, every=60), interval=60.0)
add("sparse_without_interval_hint", "fixes every 15 s but expectedIntervalS left at 1: every fix re-anchors and credits nothing", walk(120, 2.68, 14, every=15))
add("seeded_stride_gap_fill", "initialStrideM 0.95 carried over a pause: a gap 10 s after the start is filled before any stride is learned", walk(90, 2.68, 15, drop=((10, 40),), steps=True), stride=0.95)
add("seeded_stride_out_of_range", "initialStrideM 3.0 is outside 0.4-2.5 m and ignored, so the early gap is not filled", walk(90, 2.68, 16, drop=((10, 40),), steps=True), stride=3.0)
inv = walk(20, 2.68, 11)
inv.insert(5, {"type": "fix", "t": 3.0, "lat": 40.0, "lng": -75.0, "acc": 5.0, "speed": 2.6, "speedAcc": 0.3, "bearing": 10.0})
inv[8]["speed"] = 50.0
inv[9]["speedAcc"] = 3.0
inv[10]["acc"] = -1.0
inv.insert(12, {"type": "steps", "t": 9.0, "count": -5})
add("invalid_inputs", "non-monotonic t (ignored), speed>max and speedAcc>1.5 (Doppler ignored, fix kept), negative accuracy (floored), bad step count", inv)

doc = {"spec": "gps-distance-estimator v1.1",
       "reference": "docs/features/gps_distance.md",
       "tolerance_m": 0.001,
       "constants": {k: getattr(ref, k) for k in dir(ref) if k.isupper()},
       "scenarios": scen}
json.dump(doc, open(sys.argv[1], "w"), indent=1)
for s in scen:
    print(f'{s["name"]:26s} total={s["expected"]["distanceAfterEachEventM"][-1]:9.2f} steps={s["expected"]["stepDistanceM"]:7.2f} stride={s["expected"]["strideM"]}')
