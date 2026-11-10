"""Regenerate the golden vectors: python3 -I scripts/gps_distance/gen_vectors.py fixtures/gps_distance_vectors.json"""
import json, math, random, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import reference as ref
from reference import GpsDistanceEstimator

LAT0, LNG0 = 40.0, -75.0
MLAT = 111195.0


def walk(T, v, seed, sigma=3.0, rho=0.9, doppler=True, stops=(), drop=(), steps=False, cadence=2.8,
         gaps_steps=True, every=1, lat0=LAT0, lng0=LNG0, h0=0.0, speed_at=None, dop2d=None, bias=0.0, scale=1.0,
         spikes=(), jump=None, acc=None, steps_until=None, canopy=None, speed_acc=None, step_batch=None):
    """canopy: (start, length, extra_sigma_m, stated_acc_m, stated_speed_acc_mps) — a stretch
    under trees: extra white position noise, the stated accuracies, and Doppler with that
    stated speed accuracy (its noise drawn to match).
    step_batch: the pedometer's count reaches the estimator only every this many seconds
    (Android's step counter batching while the screen is off), stamped on arrival."""
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
        if steps and (step_batch is None or (t + 1) % step_batch == 0):
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
        under = canopy is not None and canopy[0] <= t < canopy[0] + canopy[1]
        if under:
            ox += r.gauss(0, canopy[2]); oy += r.gauss(0, canopy[2])
        lng = lng0 + (x + nx + ox) / mlng
        if lng >= 180.0:
            lng -= 360.0
        fix = {"type": "fix", "t": float(t),
               "lat": round(lat0 + (y + ny + oy) / MLAT, 9), "lng": round(lng, 9),
               "acc": (canopy[3] if under else round(sigma * 1.2 + abs(r.gauss(0, 1)), 2)) if acc is None else acc,
               "speed": None, "speedAcc": None, "bearing": None}
        if doppler and dop2d is not None:
            dvx = s * math.sin(h) + r.gauss(0, dop2d); dvy = s * math.cos(h) + r.gauss(0, dop2d)
            fix["speed"] = round(math.hypot(dvx, dvy), 3)
            fix["speedAcc"] = dop2d
            fix["bearing"] = round(math.degrees(math.atan2(dvx, dvy)) % 360, 2)
        elif doppler and under:
            fix["speed"] = round(abs(s + r.gauss(0, canopy[4] * 0.6)), 3)
            fix["speedAcc"] = canopy[4]
            fix["bearing"] = round((math.degrees(h) + r.gauss(0, 15)) % 360, 2) if s > 0 else None
        elif doppler:
            fix["speed"] = round(abs(s + r.gauss(0, 0.15)) * scale + bias, 3)
            fix["speedAcc"] = round(0.3 + abs(r.gauss(0, 0.1)), 3) if speed_acc is None else speed_acc
            fix["bearing"] = round((math.degrees(h) + r.gauss(0, 8)) % 360, 2) if s > 0 else None
        ev.append(fix)
    ev.sort(key=lambda e: e["t"])
    ev.append({"type": "finish", "t": float(T)})
    return ev


def evaluate(events, max_speed=10.0, interval=1.0, stride=None, learn_stride=True):
    e = GpsDistanceEstimator(max_speed, interval, stride, learn_stride=learn_stride)
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
def add(name, desc, events, max_speed=10.0, interval=1.0, stride=None, learn_stride=True):
    e, out = evaluate(events, max_speed, interval, stride, learn_stride)
    sm = ref.smooth_distance(events, max_speed, interval, stride, learn_stride)
    scen.append({"name": name, "description": desc, "maxSpeedMps": max_speed,
                 "expectedIntervalS": interval, "initialStrideM": stride, "learnStride": learn_stride,
                 "events": events,
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
add("gap_no_steps", "30 s fix gap mid-run, no pedometer: no steps to fill it, so the chord across it, less its uncertainty, is credited (v1.4)", walk(120, 2.68, 6, drop=((50, 30),)))
add("gap_with_steps", "stride learned over 80 s, then 40 s fix gap filled by steps x stride, credited at least the chord lower bound (v1.4)", walk(160, 2.68, 7, drop=((80, 40),), steps=True))
add("short_gap_with_steps", "6 s fix gap: filter integrates it, buffered steps discarded", walk(120, 2.68, 8, drop=((80, 6),), steps=True))
add("trailing_gap_with_steps", "fixes stop 30 s before finish: steps committed at finish", walk(140, 2.68, 9, drop=((110, 40),), steps=True))
add("walker", "1.3 m/s walk with Doppler", walk(120, 1.3, 10), max_speed=5.0)
add("sparse_15s", "fixes every 15 s (firmware power mode) with Doppler; expectedIntervalS 15 keeps them inside the gap window", walk(300, 2.68, 12, every=15), interval=15.0)
add("sparse_60s_position_only", "fixes every 60 s, no Doppler, expectedIntervalS 60", walk(600, 2.68, 13, doppler=False, every=60), interval=60.0)
add("sparse_without_interval_hint", "fixes every 15 s but expectedIntervalS left at 1: every fix re-anchors, credited only by the chord lower bound (v1.4)", walk(120, 2.68, 14, every=15))
add("seeded_stride_gap_fill", "initialStrideM 0.95 carried over a pause: a gap 10 s after the start is filled before any stride is learned", walk(90, 2.68, 15, drop=((10, 40),), steps=True), stride=0.95)
add("seeded_stride_out_of_range", "initialStrideM 3.0 is outside 0.4-2.5 m and ignored, so the early gap is not step-filled; its chord lower bound is credited (v1.4)", walk(90, 2.68, 16, drop=((10, 40),), steps=True), stride=3.0)
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

# v1.4 scenarios.
add("canopy_20_50", "v1.4 canopy: a 60 s stretch under trees reports 35 m accuracy (extra 12 m noise) and Doppler at speedAcc 0.9; the fixes stay in the filter, so there is no gap",
    walk(180, 2.68, 40, canopy=(60, 60, 12.0, 35.0, 0.9)))
add("canopy_beyond_50", "v1.4 canopy: a 30 s stretch reports 60 m accuracy; past MAX_POS_SIGMA_M the fixes are ignored, the stretch is a gap, and its chord lower bound is credited",
    walk(150, 2.68, 41, canopy=(60, 30, 25.0, 60.0, 0.9)))
add("canopy_poor_speed_accuracy", "v1.4 stride: steps under a 60 s canopy stretch whose Doppler states speedAcc 1.2 do not teach stride; the velocity update still takes that Doppler",
    walk(120, 2.68, 42, steps=True, canopy=(0, 120, 6.0, 30.0, 1.2)))
add("gap_chord_steps_short", "v1.4 gap: initialStrideM 0.5 is too short, so the 30 s gap's steps fall short of the chord; the GPS credit makes up the difference",
    walk(120, 2.68, 43, drop=((40, 30),), steps=True), stride=0.5)
add("fused_no_stride_learning", "v1.4 fused: learnStride false, steps throughout; no stride is learned, and the 30 s gap is credited by its chord alone",
    walk(160, 2.68, 44, drop=((80, 30),), steps=True), learn_stride=False)
add("fused_seeded_stride", "v1.4 fused: learnStride false with initialStrideM 0.95; the seeded stride fills the gap and is never updated",
    walk(160, 2.68, 45, drop=((80, 30),), steps=True), stride=0.95, learn_stride=False)

# v1.5 scenarios.
add("zupt_batched_steps", "v1.5 ZUPT window: a 1.3 m/s pocket walk on the fused provider (no Doppler, learnStride false) whose step count arrives in 15 s batches; the window stretches to 1.5 x the batch span, so walking between batches is not a stop",
    walk(300, 1.3, 50, doppler=False, steps=True, cadence=1.8, step_batch=15), max_speed=5.0, stride=0.72, learn_stride=False)
add("zupt_batched_steps_stop", "v1.5 ZUPT window: the same 15 s batches with a 60 s stop at t=150; once the stretched window passes with no new steps the stop still zeroes distance",
    walk(300, 1.3, 51, doppler=False, steps=True, cadence=1.8, step_batch=15, stops=((150, 60),)), max_speed=5.0, stride=0.72, learn_stride=False)

# v1.6 scenarios: a step sample's steps are attributed across the interval they were
# taken in, so every step the pedometer counted while no fix covered it is credited.
def line(fix_ts, step_ts, v=4.0, cadence=4.0, east_at=None, finish=None):
    """Fixes at fix_ts heading east at v m/s (Doppler, 3 m stated accuracy); the step
    count, at cadence per second, sampled at step_ts. east_at overrides a fix's
    position (metres east), for a runner who loops back during a gap."""
    mlng = MLAT * math.cos(math.radians(LAT0))
    ev = []
    for t in fix_ts:
        east = (east_at or {}).get(t, v * t)
        ev.append({"type": "fix", "t": float(t), "lat": LAT0, "lng": round(LNG0 + east / mlng, 9),
                   "acc": 3.0, "speed": v, "speedAcc": 0.3, "bearing": 90.0})
    for t in step_ts:
        ev.append({"type": "steps", "t": float(t), "count": int(round(cadence * t))})
    ev.sort(key=lambda e: (e["t"], e["type"] != "steps"))
    if finish is not None:
        ev.append({"type": "finish", "t": float(finish)})
    return ev


add("gap_steps_loop_back", "v1.6: a 1 m stride learned over 25 s, then a 30 s fix gap whose runner loops back to 10 m from where it began; all 120 steps of the gap are credited (120 m), including the two seconds just after the last fix and the half second before the resuming fix",
    line(list(range(26)) + [55], [t + 0.5 for t in range(56)], east_at={55: 110.0}), stride=1.0, learn_stride=False)
add("gap_step_batch_after_resume", "v1.6: the gap's step count arrives in 5 s batches, the last of them after the first fix past the gap; its share of the gap tops the gap's credit up to the steps",
    line(list(range(26)) + [55, 56, 57], [t + 0.5 for t in range(26)] + [30, 35, 40, 45, 50, 56.5],
         east_at={55: 110.0, 56: 114.0, 57: 118.0}), stride=1.0, learn_stride=False)
add("gap_steps_two_gaps_one_batch", "v1.6: a canopy fix at t=40 splits the 30 s stall into two gaps and a single step batch at 56.5 covers both; each gap gets its own share, so the steps still credit 120 m",
    line(list(range(26)) + [40, 55, 56, 57], [t + 0.5 for t in range(26)] + [56.5],
         east_at={40: 60.0, 55: 110.0, 56: 114.0, 57: 118.0}), stride=1.0, learn_stride=False)
def late_steps(ev, t, after_fix):
    """Move the step sample stamped t to just after the fix at after_fix: a batch the
    pedometer stamped inside a gap but delivered after the fix that closed it."""
    smp = next(e for e in ev if e["type"] == "steps" and e["t"] == t)
    ev.remove(smp)
    i = next(i for i, e in enumerate(ev) if e["type"] == "fix" and e["t"] == after_fix)
    ev.insert(i + 1, smp)
    return ev


add("gap_step_stamped_inside_delivered_late", "v1.6: 5 s step batches across a 30 s stall the runner loops back across; the 1 s batch stamped at 51 arrives after the fix at 55 closes the gap, so it claims only its own (50, 51] share (4 m, not the 20 m to the gap's end), the gap stays open, and the sample at 57.5 shares the rest (51, 55]: the steps credit all 120 m of the gap",
    late_steps(line(list(range(26)) + [55, 56, 57], [t + 0.5 for t in range(26)] + [30, 35, 40, 45, 50, 51, 57.5],
                    east_at={55: 110.0, 56: 114.0, 57: 118.0}), 51.0, 55.0), stride=1.0, learn_stride=False)
add("gap_steps_open_gap_cap", "v1.6: nine 12 s gaps whose fixes zigzag 10 m apart, with no step sample until one after the ninth; only MAX_OPEN_GAPS = 8 gaps can still claim a share, so the oldest keeps its chord credit and its 46 m of steps after the 25.5 sample are dropped (the cap only under-credits)",
    line(list(range(26)) + [25 + 12 * k for k in range(1, 10)], [t + 0.5 for t in range(26)] + [133.5],
         east_at={25 + 12 * k: (110.0 if k % 2 else 100.0) for k in range(1, 10)} | {25: 100.0}), stride=1.0, learn_stride=False)
add("steps_without_any_fix", "v1.6: initialStrideM 1.0 and steps but no fix at all; steps before a stretch's first fix are never credited, which leaves a run GPS never reached to the pedometer's indoor estimate",
    line([], [t + 0.5 for t in range(30)], finish=30.0), stride=1.0, learn_stride=False)

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
