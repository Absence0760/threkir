"""Regenerate the golden vectors: python3 -I scripts/gps_distance/gen_vectors.py fixtures/gps_distance_vectors.json"""
import json, math, random, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import reference as ref
from reference import GpsDistanceEstimator

LAT0, LNG0 = 40.0, -75.0
MLAT = 111195.0


def walk(T, v, seed, sigma=3.0, rho=0.9, doppler=True, stops=(), drop=(), steps=False, cadence=2.8,
         gaps_steps=True, every=1, lat0=LAT0, lng0=LNG0, h0=0.0, speed_at=None, dop2d=None, bias=0.0, scale=1.0,
         spikes=(), jump=None, acc=None, steps_until=None):
    r = random.Random(seed)
    mlng = MLAT * math.cos(math.radians(lat0))
    x = y = 0.0; h = math.radians(h0); nx = ny = 0.0; k = math.sqrt(1 - rho * rho); ev = []; cnt = 0; stepacc = 0.0
    for t in range(T):
        stopped = any(a <= t < a + l for a, l in stops)
        s = 0.0 if stopped else (speed_at(t) if speed_at else v)
        if t % 40 == 0 and t: h += math.radians(70 if (t // 40) % 2 else -50)
        x += s * math.sin(h); y += s * math.cos(h)
        nx = rho * nx + k * r.gauss(0, sigma); ny = rho * ny + k * r.gauss(0, sigma)
        if steps and s > 0 and (steps_until is None or t < steps_until):
            stepacc += cadence
        if steps:
            cnt = int(stepacc)
            ev.append({"type": "steps", "t": float(t) + 0.5, "count": cnt})
        if any(a <= t < a + l for a, l in drop) or t % every:
            continue
        ox = oy = 0.0
        for st, dx, dy in spikes:
            if st == t:
                ox += dx; oy += dy
        if jump is not None and t >= jump[0]:
            ox += jump[1]; oy += jump[2]
        lng = lng0 + (x + nx + ox) / mlng
        if lng >= 180.0:
            lng -= 360.0
        fix = {"type": "fix", "t": float(t),
               "lat": round(lat0 + (y + ny + oy) / MLAT, 9), "lng": round(lng, 9),
               "acc": round(sigma * 1.2 + abs(r.gauss(0, 1)), 2) if acc is None else acc,
               "speed": None, "speedAcc": None, "bearing": None}
        if doppler and dop2d is not None:
            dvx = s * math.sin(h) + r.gauss(0, dop2d); dvy = s * math.cos(h) + r.gauss(0, dop2d)
            fix["speed"] = round(math.hypot(dvx, dvy), 3)
            fix["speedAcc"] = dop2d
            fix["bearing"] = round(math.degrees(math.atan2(dvx, dvy)) % 360, 2)
        elif doppler:
            fix["speed"] = round(abs(s + r.gauss(0, 0.15)) * scale + bias, 3)
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
    sm = ref.smooth_distance(events, max_speed, interval, stride)
    scen.append({"name": name, "description": desc, "maxSpeedMps": max_speed,
                 "expectedIntervalS": interval, "initialStrideM": stride, "events": events,
                 "expected": {"distanceAfterEachEventM": out,
                              "gpsDistanceM": round(e.gps_distance_m, 6),
                              "stepDistanceM": round(e.step_distance_m, 6),
                              "strideM": None if e.stride_m is None else round(e.stride_m, 6),
                              "rejectedFixes": e.rejected_fixes,
                              "zuptFixes": e.zupt_fixes,
                              "rScale": round(e.r_scale, 6),
                              "dopplerTrusted": e.doppler_trusted,
                              "dopplerScale": round(e.doppler_scale, 6)},
                 "smoothed": {"distanceAfterEachEventM": [round(c, 6) for c in sm["cumulative_m"]],
                              "distanceM": round(sm["distance_m"], 6),
                              "gpsDistanceM": round(sm["gps_distance_m"], 6),
                              "stepDistanceM": round(sm["step_distance_m"], 6),
                              "stoppedFixes": sm["stopped_fixes"],
                              "positions": [None if p is None else [round(p[0], 9), round(p[1], 9)]
                                            for p in sm["positions"]]}})


add("doppler_run", "120 s run at 2.68 m/s with Doppler speed + bearing; true distance 318.9 m", walk(120, 2.68, 1))
add("position_only_run", "120 s run with no Doppler (legacy track); true distance 318.9 m", walk(120, 2.68, 2, doppler=False))
add("stationary_doppler", "90 s standing still with jitter; Doppler ~0.15 m/s; expect ~0", walk(90, 0.0, 3))
add("stationary_position_only", "90 s standing still, no Doppler; expect ~0 (forward drifts, smoother's stop detection does not)", walk(90, 0.0, 4, doppler=False))
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

# v1.2 scenarios.
add("outlier_spikes_position_only", "v1.2 gate: three 35-45 m multipath spikes reported at ~4 m accuracy, no Doppler; the gate rejects them",
    walk(120, 2.68, 20, doppler=False, spikes=((30, 40.0, -10.0), (61, -30.0, 25.0), (90, 10.0, 44.0))))
add("gate_lockout_jump", "v1.2 gate lock-out: the fixes jump 60 m sideways at t=50 and stay there; after 5 rejections the next fix re-anchors position",
    walk(120, 2.68, 21, doppler=False, jump=(50, 60.0, 0.0)))
add("doppler_bias", "v1.2 cross-check: Doppler reads 0.6 m/s high for the whole 420 s run; it is distrusted and the position path takes over",
    walk(420, 2.68, 22, bias=0.6))
add("optimistic_accuracy", "v1.2 adaptive R: fixes scatter with sigma 8 m but report 3 m, no Doppler; rScale rises above 1",
    walk(240, 2.68, 23, sigma=8.0, rho=0.6, doppler=False, acc=3.0))
add("zupt_stop_with_steps", "v1.2 ZUPT: 40 s stop at t=60 with the pedometer reporting no new steps, no Doppler; distance stops after ZUPT_NO_STEP_S",
    walk(150, 2.68, 24, doppler=False, steps=True, stops=((60, 40),)))
add("zupt_doppler_override", "v1.2 ZUPT: the pedometer stops counting at t=40 while Doppler says 2.7 m/s; Doppler overrides the ZUPT",
    walk(120, 2.68, 25, steps=True, steps_until=40))
add("zupt_release_dead_pedometer", "v1.2 ZUPT release: the pedometer stops counting at t=40, no Doppler; after the filter moves ZUPT_RELEASE_M the ZUPT releases and the chord is credited",
    walk(120, 2.68, 26, doppler=False, steps=True, steps_until=40))
add("legacy_stop_clustering", "v1.2 smoother: 60 s stop in a position-only track; post-hoc stop detection flags it in the smoothed figure",
    walk(180, 2.68, 27, doppler=False, stops=((70, 60),)))
add("low_speed_walk_doppler", "v1.2 debias: 0.8 m/s walk with honest 2-D Doppler noise (sigma 0.3); raw speed reads high, the debiased speed does not",
    walk(120, 0.8, 28, dop2d=0.3), max_speed=5.0)
add("antimeridian_crossing", "v1.2 projection: eastward position-only run at -17 deg latitude across lng 180; the longitude difference wraps, so the crossing is an ordinary 2.7 m hop",
    walk(120, 2.68, 29, doppler=False, lat0=-17.0, lng0=179.9995, h0=90.0))
add("smoother_pace_change", "v1.2 smoother: position-only, alternating 2.0 and 4.0 m/s every 40 s; true distance 478 m",
    walk(160, 2.68, 30, doppler=False, speed_at=lambda t: 2.0 if (t // 40) % 2 == 0 else 4.0))

# v1.3 scenarios.
add("doppler_scale_low", "v1.3 Doppler scale: Doppler reads 8% low for the whole 420 s run (an iPhone); the learned scale rises to about 1.07 and distance follows the fixes",
    walk(420, 2.68, 31, scale=0.92))
add("doppler_scale_high", "v1.3 Doppler scale: Doppler reads 10% high for the whole 420 s run (a fused-provider Android); the learned scale falls to about 0.93",
    walk(420, 2.68, 32, scale=1.10))

doc = {"spec": "gps-distance-estimator v" + ref.SPEC_VERSION,
       "reference": "docs/features/gps_distance.md",
       "tolerance_m": 0.001,
       "position_tolerance_deg": 1e-8,
       "constants": {k: getattr(ref, k) for k in dir(ref) if k.isupper() and k != "SPEC_VERSION"},
       "scenarios": scen}
def dump(o, ind=0):
    """indent=1 JSON, but each event, position pair and number list on one line."""
    pad = " " * (ind + 1)
    if isinstance(o, dict) and not (o.get("type") in ("fix", "steps", "finish")):
        return "{\n" + ",\n".join(pad + json.dumps(k) + ": " + dump(v, ind + 1) for k, v in o.items()) + "\n" + " " * ind + "}"
    if isinstance(o, list) and any(isinstance(v, dict) or isinstance(v, list) for v in o):
        return "[\n" + ",\n".join(pad + dump(v, ind + 1) for v in o) + "\n" + " " * ind + "]"
    return json.dumps(o, separators=(", ", ": "))


with open(sys.argv[1], "w") as f:
    f.write(dump(doc) + "\n")
for s in scen:
    x, m = s["expected"], s["smoothed"]
    print(f'{s["name"]:30s} fwd={x["distanceAfterEachEventM"][-1]:9.2f} smooth={m["distanceM"]:9.2f} '
          f'steps={x["stepDistanceM"]:7.2f} stride={x["strideM"]} rej={x["rejectedFixes"]} zupt={x["zuptFixes"]} '
          f'rScale={x["rScale"]:.3f} trusted={x["dopplerTrusted"]} scale={x["dopplerScale"]:.3f} stopped={m["stoppedFixes"]}')
