# GPS distance estimator (spec v1.2)

How every recorder in the estate turns a stream of GPS fixes into a distance. One algorithm, seven ports, one set of golden vectors.

Spec v1.2 (issue #1090) keeps every v1.1 behaviour and adds: an innovation gate against outlier fixes, adaptive measurement noise, a Doppler-vs-position cross-check, a low-speed Doppler debias, a pedometer zero-velocity update, an antimeridian-safe projection, and a **smoother** (forward pass plus Rauch-Tung-Striebel backward pass, with post-hoc stop detection for tracks with no Doppler) that produces the saved and recomputed figures. Live screens keep the forward filter.

## Why it exists

Until v1, every recorder (Flutter `RunRecorder`, Wear OS `RunRecordingService`, watchOS `WorkoutManager`, the custom-watch firmware) summed the straight-line hop between consecutive raw fixes and dropped hops under a 2-3 m floor. At running pace a 1 Hz fix moves ~2.7 m, the same size as the fix error, so the summed path zig-zags across the true line and every zig-zag adds length. A field report (2026-10-08) had a 3.1 mi course recorded as 3.92 mi (+26%) on a phone while a Garmin watch read ~3.1 mi.

## Bench

`python3 -I scripts/gps_distance/bench.py` runs a synthetic course (1850 s, turns every 90 s unless stated) with time-correlated phone noise, mean of 5 seeds, worst seed in brackets. The v1.1 column is the previous reference run over the same inputs. **Synthetic only**: the constants are not validated against ground truth until the corpus below exists.

| Scenario | Hop-sum | v1.1 | v1.2 forward (live) | v1.2 smoothed (saved) |
|---|---|---|---|---|
| sigma 3 m, rho 0.9 | +18.5% | +0.2% | +0.2% [+0.3] | +0.2% [+0.3] |
| sigma 3 m, rho 0.9, two stops | +25.9% | +0.5% | +0.3% [+0.4] | +0.3% [+0.4] |
| sigma 4 m, rho 0.95, two stops | +44.5% | +0.5% | +0.3% [+0.4] | +0.3% [+0.4] |
| sigma 3 m, rho 0.9, position-only | +17.7% | +0.8% | +0.8% [+1.2] | -0.1% [-0.5] |
| sigma 3 m, two stops, position-only | +24.8% | +2.3% | +2.3% [+2.7] | -0.1% [-0.5] |
| sigma 4 m, rho 0.95, two stops, position-only | +43.7% | +1.8% | +1.8% [+2.5] | -0.4% [-1.1] |
| Android 5 s fixes, sigma 4 m | +1.9% | +0.1% | +0.1% [+0.2] | +0.1% [+0.2] |
| multipath spikes 3% (25-60 m), Doppler | +104% | +0.4% | +0.4% [+0.7] | +0.4% [+0.7] |
| multipath spikes 3%, position-only | +100% | +7.1% | +1.2% [+1.5] | +0.3% [+0.5] |
| optimistic accuracy (true 8 m, stated 3 m), position-only | +242% | +29.0% | +13.5% [+14.8] | +4.7% [+6.3] |
| Doppler biased +0.5 m/s | +18.5% | +18.8% | +4.2% [+5.8] | +3.4% [+5.1] |
| slow walk 1.0 m/s, Doppler sigma 0.3 (honest accuracy) | +86.5% | +3.8% | +2.0% [+2.8] | +2.0% [+2.8] |
| slow walk 1.0 m/s, Doppler sigma 0.15 stated 0.5 (pessimistic) | +86.5% | +0.9% | -0.9% [-1.5] | -0.9% [-1.5] |
| pace change 2 / 4 m/s every 60 s, position-only | +15.4% | +0.6% | +0.6% [+0.9] | -0.2% [-0.7] |
| forest trail: 90 deg turn every 25 s, sigma 6 m, rho 0.97 | +82.8% | +0.9% | +0.9% [+1.7] | +0.9% [+1.7] |
| forest trail, position-only | +82.7% | -1.2% | -1.2% [-1.6] | **-3.1% [-3.5]** |
| canopy switchbacks: 150 deg every 12 s, sigma 6 m | +82.4% | +1.0% | +1.0% [+1.2] | +1.0% [+1.2] |
| canopy switchbacks, position-only | +81.5% | -19.5% | -19.5% [-22.3] | **-31.3% [-34.7]** |
| urban canyon: sigma 8 m, rho 0.98, spikes 5%, turns every 30 s | +200% | +1.1% | +1.1% [+1.7] | +1.1% [+1.7] |

Reading it:

- **With Doppler** (every run recorded since v1) v1.2 never under-counts on the twisty and canopy courses (Gilgen-Ammann 2020 found sport watches under-read by up to 9% in forest and urban areas, so this was checked explicitly). The new rows that move are the biased-Doppler chipset (+18.8% to +4.2%; what remains is the ~180 s before the cross-check's verdict) and slow walking under cover (+3.8% to +2.0%).
- **Position-only** (legacy tracks, server recompute): the gate and adaptive R cut the outlier and optimistic-accuracy rows hard, and the smoother removes the stationary drift and most of the residual zig-zag. **Known limit:** on twisty position-only tracks the constant-velocity model cuts corners, and the smoother, which estimates velocity from both sides of each turn, cuts them more than the forward filter (-3.1% against -1.2% on the forest trail; -31% against -19.5% on 12 s switchbacks). The cause is `Q_ACCEL` (below), not the smoother; the durable fix is a maneuver-adaptive or per-activity process noise tuned on the corpus's tree-covered course. Until then the server recompute keeps the forward pass for a position-only track that is not a road run (Server recompute, step 3), which still under-reads a tight switchback trail, by less.
- The pessimistic-accuracy slow walk shows the debias trade-off: a platform that overstates `speedAccuracy` makes the debias subtract too much, which is why it fades out by 1.0 m/s.

## Algorithm

The reference implementation is [`scripts/gps_distance/reference.py`](../../scripts/gps_distance/reference.py) (stdlib Python, scalar float64 only). It is the spec; this page explains it. The exact per-fix order of operations is in **Porting notes** at the end.

1. **Projection.** The first valid fix fixes a local tangent plane: `x = rad(wrap(lng - lng0)) * R * cos(rad(lat0))`, `y = rad(lat - lat0) * R`, `R = 6371008.8`. `wrap(d)` maps a longitude difference into [-180, 180) (`d >= 180: d - 360`, `d < -180: d + 360`), so a run across the antimeridian is an ordinary hop instead of a 40,000 km jump (v1.2). The inverse (`unproject`) wraps the output longitude the same way.
2. **Filter.** Two independent 1-D constant-velocity Kalman filters (x and y), state `[p, v]`, covariance `[[a, b], [b, c]]`, white-acceleration process noise `Q_ACCEL = 0.6 m^2/s^3`. Stated position variance is `r_stated = max(accuracy, 3 m)^2` (missing / non-positive accuracy reads as 3 m). The variance actually used is `r = max(r_stated * rScale, 9)` (v1.2, item 5).
3. **Innovation gate (v1.2).** After the predict, the 2-D normalised innovation squared `NIS = yx^2 / (ax + r) + yy^2 / (ay + r)` (y = measurement minus prediction, ax / ay the predicted position variances) is compared with `GATE_CHI2 = 13.8155` (chi-square, 2 dof, p = 0.001). A rejected fix skips the position update only: time still advances, Doppler still updates the velocity, and it is still credited (credit comes from speed, not position). **Lock-out guard:** after `GATE_MAX_REJECTS = 5` consecutive rejections the next rejected fix re-anchors position (`p = z`, `a = r`, `b = 0`, velocity kept), so a genuine jump (a tunnel exit, a multipath state that persists) cannot lock the filter out.
4. **Adaptive R (v1.2).** Covariance matching on accepted fixes: `sample = ((yx^2 - ax) + (yy^2 - ay)) / (2 * r_stated)`, clamped to [0, 9], then `rScale = clamp(0.95 * rScale + 0.05 * sample, 1, 9)`, used from the next fix. It only **inflates**: under time-correlated GPS error the innovations look small because the error is slowly varying, not because it is small, so deflating R below the stated accuracy made the position-only bench over-count more (an `R_SCALE_MIN` of 0.5 gave +1.2% to +3.2% where 1.0 gives +0.8% to +2.3%). Multipath is biased and persistent rather than sparse, so the gate alone cannot catch it (research note 13); adaptive R is what handles a platform that is consistently optimistic.
5. **Doppler.** The chip's own speed (`Position.speed` / `Location.speed` / `CLLocation.speed`, from the carrier Doppler shift). Usable when finite, `0 <= speed <= maxSpeed`, and its accuracy (default 0.5 m/s when unreported) is `<= 1.5 m/s`. **Low-speed debias (v1.2):** when the platform reported `speedAccuracy` (`sa`), `s' = sqrt(max(0, s^2 - w * sa^2))` with `w = 1` at `s <= 0.5 m/s`, fading linearly to `w = 0` at `s = 1.0 m/s`. Why: the speed is the magnitude of a noisy 2-D velocity, Rician-distributed, so `E[s^2] = v^2 + 2 sigma^2` and at `v = 0` it is Rayleigh with mean `1.25 sigma` (it never reads zero). With isotropic error, `s^2 - sa^2` is first-order unbiased for `v^2` at speed and removes ~40% of the Rayleigh bias at a standstill. It is faded out because platforms usually overstate `sa` (Li et al. 2022 measured cm/s-to-dm/s actual error) and a pessimistic `sa` over-corrects into under-counting, the failure Gilgen-Ammann warns about; above ~1 m/s the raw bias `sigma^2 / 2v` is small anyway. When a bearing is present and `s' >= 0.4 m/s`, the speed vector updates the velocity with variance `max(sa, 0.3)^2` (unchanged), unless the cross-check has distrusted Doppler or a ZUPT applies.
6. **Doppler cross-check (v1.2).** Some chipsets carry a constant Doppler bias (Peng et al. 2023) that the v1.1 design integrated straight into distance. On each accepted fix with usable Doppler at `>= 0.8 m/s`, a bearing, no ZUPT, and a span to the previous accepted fix `<= 5 s`, the raw displacement since that fix is projected on the Doppler bearing: `u = (dx sin b + dy cos b) / span`. This is unbiased on turns, where a filtered speed cuts corners (an earlier draft compared against a position-only filter's speed and distrusted good Doppler on every twisty course). Both speeds feed EMAs (`tau = 60 s`, `alpha = min(1, span / tau)`, both seeded with the Doppler speed). After `XCHECK_MIN_S = 120 s` of compared time, the verdict flips when the disagreement holds for `XCHECK_PERSIST_S = 60 s`: distrust when `|ema_dop - ema_u| > max(0.4, 0.15 |ema_u|)`, trust again when `< max(0.2, 0.08 |ema_u|)`. While distrusted, Doppler neither updates the velocity nor earns credit, so the fix credits through the position path; the EMAs keep running so it can recover. Biases below ~0.4 m/s are not detected (the bench's correlated position noise moves the EMA by ~0.2 m/s on twisty courses).
7. **Zero-velocity update (v1.2).** Once the pedometer has reported **any** step increase this run, a fix more than `ZUPT_NO_STEP_S = 6 s` after the last increase is stationary: both axes get a velocity pseudo-measurement `0` with variance `0.1^2`, no Doppler velocity update, no cross-check sample, and **no credit**. Trusted Doppler at `>= 1.0 m/s` overrides it (a runner whose pedometer lags a restart). **Release guard:** while a pedometer ZUPT holds, the filtered position is compared with where the ZUPT started; past `ZUPT_RELEASE_M = 40 m` the pedometer is taken as stalled, the ZUPT releases until the next step increase, and that fix credits the 40+ m chord instead of its speed. That keeps a dead step sensor from freezing distance (layered resilience: the pedometer is a higher layer than GPS distance). **`ZUPT_NO_STEP_S` must be measured on device**: Android delivers step-counter events in batches that lag several seconds, so too small an N turns every batch interval into a stop.
8. **Credit.** Per fix: zero if a ZUPT applies; else `speed = debiased Doppler` if usable and trusted (floor 0.4 m/s), else `|filtered velocity|` (floor 0.8 m/s). Below the floor the fix credits **zero** — this is what kills red-light drift. Otherwise `min(speed, maxSpeed) * dt`. A ZUPT release credits its chord.
9. **Gaps.** `dt > gapWindow` re-anchors the filter at the new fix and credits nothing (`gapWindow = 10 s x max(1, expectedIntervalS)`). A non-increasing timestamp is ignored. The cross-check's last position and the gate streak reset at a re-anchor; the cross-check EMAs, `rScale` and the trust verdict carry across it.
10. **Pedometer gap fill.** Unchanged from v1.1: `addSteps(t, cumulative)` learns a stride while GPS is good (a fix within `2 s x max(1, expectedIntervalS)`, every 50 steps, 0.4-2.5 m, EMA 0.2); while GPS is not good, steps x stride accumulate in a pending buffer (capped at `maxSpeed * dt`) that is committed only if the gap exceeds the gap window, or at `finish(t)` when the run ends in a gap. `initialStrideM` carries a stride across a pause. v1.2 adds only the ZUPT bookkeeping (`stepsSeen`, `lastStepIncreaseT`, clearing `zuptReleased`) on every increase.
11. **Outputs.** `distance = gpsDistance + stepDistance`, plus `stepDistance` and `stride` for metadata, and the diagnostics `rejectedFixes`, `zuptFixes`, `rScale`, `dopplerTrusted`.

The forward estimator only decides **distance**. The track (the waypoints stored, drawn and route-matched) keeps each recorder's existing movement-gated append rule.

## Smoother (v1.2): the saved and recomputed figure

`smooth_distance(events, maxSpeedMps, expectedIntervalS, initialStrideM)` takes the run's whole event stream (fixes, step counts, finish, in arrival order) and returns:

| Output | Meaning |
|---|---|
| `distance_m` | smoothed GPS distance + step distance |
| `gps_distance_m`, `step_distance_m` | the two parts |
| `cumulative_m[i]` | per **event**: smoothed GPS credit through event `i` plus the step distance committed by then (the embedded-best cumulative) |
| `positions[i]` | per **event**: `(lat, lng)` of the smoothed position for an accepted fix, `None` for a steps / finish event or an ignored fix (the filtered line stored alongside the raw track, item 7) |
| `stopped_fixes` | how many fixes post-hoc stop detection flagged |

Steps:

1. **Accepted fixes.** The same rule as the estimator: finite `t` / `lat` / `lng`, `t` strictly greater than the last accepted fix. The first valid fix sets the projection origin.
2. **Post-hoc stop detection, only when no accepted fix carries a finite `speed`** (a legacy track): for each accepted fix `j`, half-window `H = 20 s x max(1, expectedIntervalS)`, set A = fixes with `t_j - H <= t < t_j`, B = fixes with `t_j <= t <= t_j + H` (B includes `j`). Fix `j` is stopped when A and B each hold at least 3 fixes, the net speed `|mean(B) - mean(A)| / (meanT(B) - meanT(A)) < 0.5 m/s`, **and** the RMS distance of A plus B from their joint mean `< 10 m`. The RMS test is what keeps an out-and-back turnaround (two halves with the same mean) from reading as a stop. Means are plain sums in index order divided by the count; projected raw positions are used.
3. **Forward pass.** A fresh `GpsDistanceEstimator` replays the events, each stopped fix passed `stopped_hint = true` (treated exactly like a ZUPT: zero-velocity pseudo-measurement, no Doppler update, no credit, no release check). It records, per accepted fix: whether it is a gap anchor, whether it starts a new **chain** (an anchor or a gate lock-out re-anchor), `dt`, the predicted state and covariance per axis (after predict, before any update), the final filtered state and covariance per axis, the ZUPT flag, the usable-and-trusted debiased Doppler speed (or none), the release chord (or none) and the step distance committed so far. Stride learning uses this pass's forward credit.
4. **Backward pass (RTS)** per chain, per axis, independently. The last fix of a chain keeps its filtered state; for `k` from the second-to-last down: with filtered `(p, v, a, b, c)` at `k` and the next fix's `dt` and predicted `(pp, pv, A, B, C)`: `det = A C - B^2`, `g00 = ((a + dt b) C - b B) / det`, `g01 = (b A - (a + dt b) B) / det`, `g10 = ((b + dt c) C - c B) / det`, `g11 = (c A - (b + dt c) B) / det`, `dp = ps[k+1] - pp`, `dv = vs[k+1] - pv`, `ps[k] = p + g00 dp + g01 dv`, `vs[k] = v + g10 dp + g11 dv`. Gap segments are independent; a lock-out starts a new chain but not a new credit segment.
5. **Credit** per fix `k` that is not a gap anchor: the release chord if it has one, else `0.5 * (eff[k-1] + eff[k]) * dt` (trapezoid), where `eff` is 0 under ZUPT / stop hint, else the recorded trusted Doppler speed with floor 0.4, else the smoothed `hypot(vx, vy)` with floor 0.8, capped at `maxSpeed`. The trapezoid uses the fix before `k` in the record, which for the first fix after an anchor is the anchor itself, whose smoothed velocity is meaningful (the backward pass reaches it).

What the smoother changes: credit stops lagging the speed it follows (both sides of each pace change are seen), stationary drift on legacy tracks goes (stop detection), and positions are smoothed (lower RMS error than the forward filter's). With trusted Doppler the credit speed is the same Doppler speed the forward filter uses, so the smoothed and forward totals differ only by the trapezoid; the benefit concentrates on position-only tracks.

**Who uses which.** Live distance and live pace: the forward estimator. Saved distance at the end of a phone run, embedded bests, and the server recompute: the smoother (ports: Dart, TS, Deno, Go). The watches keep the forward filter: the smoother needs the whole run in memory, and the phone or server re-derives the saved figure from the uploaded track.

## Waypoint fields

So the server can recompute distance from a stored track with the same Doppler input, each waypoint carries four optional keys alongside `lat` / `lng` / `elevationMetres` / `timestamp` / `bpm`:

| Key | Unit | Source |
|---|---|---|
| `accuracyMetres` | m | horizontal accuracy |
| `speedMps` | m/s | Doppler speed (omit when invalid / negative) |
| `speedAccuracyMps` | m/s | speed accuracy (omit when not reported) |
| `bearingDeg` | degrees clockwise from north | course over ground (omit when invalid) |
| `smoothedLat` / `smoothedLng` | degrees | the smoother's position for that fix, written by the phone at save; both or neither, raw `lat` / `lng` never altered |

Old tracks have none of them and recompute through the position-only path, with post-hoc stop detection.

Readers that draw the line, route-match or match pace segments prefer the smoothed pair when both halves are present (web `lib/runs/track_line.ts`, Dart `Waypoint.lineLat` / `lineLng`, Go `parseTrack`); the estimator always reads raw. Watch tracks arrive without the pair, and the server recompute does not add it: Supabase Storage has no conditional upload and clients overwrite the same object path, so a worker rewrite could clobber a concurrent re-upload. Adding it server-side needs a sidecar object or a track version guard.

## Ports

| Port | Path | Forward | Smoother |
|---|---|---|---|
| Reference (Python) | `scripts/gps_distance/reference.py` | yes | yes |
| Dart (phone) | `packages/run_recorder/lib/src/gps_distance_estimator.dart` | yes | yes |
| TypeScript (web, canonical pair) | `apps/web/src/lib/runs/gps_distance.ts` | yes | yes |
| Deno (Strava importer) | `apps/backend/supabase/functions/_shared/gps_distance.ts` | yes | yes |
| Go (server recompute) | `apps/job_worker/internal/gpsdistance/` | yes | yes |
| Kotlin (Wear OS) | `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/recording/GpsDistanceEstimator.kt` | yes | no |
| Swift (watchOS) | `apps/watch_ios/WatchApp/GpsDistanceEstimator.swift` | yes | no |
| Rust `no_std` (custom watch) | `apps/custom_watch/core/src/gps_distance.rs` | yes | no |

Every port has a test that replays [`fixtures/gps_distance_vectors.json`](../../fixtures/gps_distance_vectors.json) (27 scenarios) and asserts the forward distance after **every** event to `tolerance_m` (1e-3 m); smoother ports also assert the smoothed block. Changing the algorithm means editing `reference.py`, regenerating with `python3 -I scripts/gps_distance/gen_vectors.py fixtures/gps_distance_vectors.json`, and updating every port in the same change, bumping the spec version.

The rolling embedded bests (`estimatorCumulativeMetres`: Dart `apps/mobile_android/lib/embedded_bests.dart`, TS `apps/web/src/lib/integrations/garmin-fit.ts`, Go `apps/job_worker/internal/embedded_bests.go`) replay a stored track (`t` in seconds since the first timestamped waypoint, `expectedIntervalS` the median positive fix interval, the activity's `maxSpeedMps`) and, from v1.2, run the fastest-window search over the smoother's `cumulative_m`.

An importer whose file carries its own per-point distance stream measures the bests on that stream instead (`deviceCumulativeMetres`, in `garmin-fit.ts`, `_shared/strava.ts` and `embedded_bests.dart`): FIT `record.distance` from the web Garmin / Strava-ZIP importers and the mobile Strava-ZIP importer (`FitParser.parseWithDistances`), and Strava's `distance` stream in the Deno importer. It is what the device measured, and it is what Strava does. The stream falls back to the estimator when it is absent, misaligned with the track, or has any missing, non-finite, negative or backward sample, or no distance at all. Note that Strava's stream is Strava's own figure: for an activity uploaded without one it is Strava's outlier-trimmed straight-line sum, not a device measurement.

A road run that the OSRM `map_match` job matched end to end also gets `metadata.distance_map_matched_m`, its length along the foot graph, shown read-only on web `/runs/[id]` beside `distance_m` and never replacing it. Trails, a running track, indoor runs and anything the matcher could not measure whole get none ([metadata.md](../backend/metadata.md) lists the rules).

## Server recompute

Runs recorded before v1 keep their inflated hop-sum distance until something re-derives it. The server can, from the stored track:

1. **UI.** On `/runs/[id]` the owner sees **Recalculate distance** under the key stats when `canRecomputeDistance` (`apps/web/src/lib/runs/distance_recompute.ts`) holds: they own the run, it has a `track_url`, its `source` is `app` or `watch` (an import's distance belongs to the system that recorded it), `metadata.distance_source` is not `pedometer` (no GPS to recompute from), and `metadata.distance_estimator` is not already the **current** estimator, `kalman_v2`. The action opens a ConfirmDialog saying the distance will be recomputed with the improved GPS filter and the original kept, then calls the RPC. Success shows "Recalculating — refresh in a minute" and hides the action; a refusal (not the owner, no track) or any other failure is shown as an error toast and the action stays offered.
2. **RPC.** `request_distance_recompute(p_run_id uuid) returns void` (migration `20270719000001`) is SECURITY DEFINER, `authenticated`-only, raises `42501` unless the caller owns the run and `22000` when it has no track, and inserts a `distance_recompute` job with payload `{run_id, user_id}`. A partial unique index (`jobs_dedupe_distance_recompute`) makes a second request while one is queued or running a no-op. See [api_database.md](../backend/api_database.md).
3. **Job.** The Go worker (`apps/job_worker/internal/handler_distance_recompute.go`) downloads the track, replays its waypoints through the **smoother** (`internal/gpsdistance/`; the Doppler path when the waypoints carry `speedMps` and friends, position-only with post-hoc stop detection otherwise) with the activity's speed ceiling and the track's median fix interval as `expectedIntervalS`, and rewrites `runs.distance_m` (the stored track file itself is left as it is). It skips sources other than `app` / `watch`. **Which pass it keeps:** the smoothed figure for every track that carries Doppler, and for a position-only track that is a road run. A position-only track that is **not** a road run keeps the smoother's **forward pass** (the forward filter over the same events, with the same post-hoc stop hints), because off road the smoother cuts more corners than the forward filter (Bench, Known limit). "Road run" is the map_match step's own classifier, `roadDistanceFor` (`internal/road_distance.go`, the rules in [metadata.md § `distance_map_matched_m`](../backend/metadata.md)): the run already carries `distance_map_matched_m`, or the OSRM matcher measures the track now and the classifier accepts it against the smoothed figure (an old run's stored `distance_m` is the inflated hop-sum, so it is not the yardstick). No matcher configured, a match failure, or any rule the classifier refuses on (a hike, a trail route, a `sub_sport` of `trail`, a track-sized footprint, a run not matched end to end) keeps the forward pass. The bests in step 4 are measured on the same pass, and step 5 records it as `distance_estimator_pass`.
4. **Embedded bests.** The same replay's smoothed cumulative distance re-derives the four rolling bests (`runs.fastest_5k_s` / `_10k_s` / `_half_marathon_s` / `_marathon_s`, `internal/embedded_bests.go`), written in the same conditional PATCH as `distance_m`. All four are written: a best the inflated hop-sum produced on a run the estimator now measures short of that distance is cleared to null rather than left behind. The `personal_records` statement trigger re-derives on any change to `distance_m` or a `fastest_*` column ([derived_state.md](../backend/derived_state.md)), so the owner's PRs follow.
5. **Metadata.** The worker writes `distance_estimator = "kalman_v2"` (spec v1.2 smoother; `"kalman_v1"` was the v1 / v1.1 forward filter) and `distance_recomputed_at`, and copies the recorder's figure into `distance_recorded_m` (only when absent, so a second recompute never loses the original). The page shows it as "Originally recorded: X" in the viewer's unit. All keys are registered in [metadata.md § Distance estimator](../backend/metadata.md). **A run already recomputed as `kalman_v1` is eligible again**: the recompute gate compares against the current value, so the owner can re-run it and pick up the gate, the cross-check and the smoother; `distance_recorded_m` still holds the original recorder figure.
6. **Badges.** The same write takes back any distance badge (`distance_single`, `distance_lifetime`) the corrected distance no longer earns, via the `runs_achievements_revoke_on_distance_recompute` trigger; every other badge family stays durable ([achievements.md](achievements.md)).
7. **Stale copies.** A client that loaded the run before the recompute (the screen the owner tapped Recalculate on, an unsynced local row) cannot write the inflated figure back: the `runs_keep_distance_recompute` BEFORE UPDATE trigger (`20270719000003`) recognises a write whose metadata lacks `distance_recomputed_at` on a row that has it, carries the recompute's keys forward, keeps the recomputed `fastest_*` columns, and keeps the recomputed `distance_m` when the incoming figure is the original `distance_recorded_m`. A distance the owner deliberately typed is kept.

## Ground-truth corpus

`fixtures/gps_corpus/` holds tracks recorded on courses of measured length, each with a manifest giving the known distance, course type, device and an error budget; `scripts/gps_distance/replay_corpus.py` replays every entry through `reference.py` in CI and fails outside budget, printing the signed error, the mean NIS and the residual autocorrelation for tuning. It holds one synthetic entry until the owner's real tracks land; [its README](../../fixtures/gps_corpus/README.md) lists what to record.

Ground truth is a measured or surveyed course (a 400 m track in lane 1, a wheel-measured road loop, a tree-covered trail), never a watch reading: sport watches are themselves 3-6% off and under-read by up to 9% in forest and urban areas (Gilgen-Ammann 2020). The corpus is what every constant in this spec waits on; each course states an error budget and CI asserts the reference stays inside it. It must check **under**-counting under trees and between buildings as well as over-counting, because heavy smoothing cuts corners (the position-only rows of the bench above). It is also where the open device questions get answered: the fused provider against raw `GPS_PROVIDER` on Android, the error autocorrelation *C* (Ranacher 2015), how honest each platform's `speedAccuracy` is (which decides the debias fade), and the Android pedometer batching lag (which decides `ZUPT_NO_STEP_S`).

## Q_ACCEL is still unvalidated

`Q_ACCEL = 0.6 m^2/s^3` is the one number every part of the filter depends on — how fast the filter believes velocity can change — and it has never been checked against a real track. No published process-noise value for GPS running exists (research note 12); a pedestrian pace-estimation patent uses a separate value per motion class. v1.2 deliberately leaves it alone: tuning it on synthetic noise would fit the bench, not runners. The bench shows what it costs: too low a value cuts corners on twisty position-only tracks (forest trail -1.2% forward, -3.1% smoothed; 12 s switchbacks -20% / -31%), too high a value lets jitter through (raising it to 2 moves the open-course position-only rows from +0.8% to +2.2% forward). On the corpus it should be tuned per activity type with innovation (NIS) and NEES consistency checks, and a maneuver-adaptive variant (inflating Q when normalised innovations stay high) evaluated as the durable fix for the switchback case. Any change goes through `reference.py`, regenerates the vectors and bumps the spec version.

## Tuning

The constants are in the fixture's `constants` block. Do not tune a port independently — the vectors will fail, which is the point.

Known limits: position-only input (live forward filter) still drifts ~15 m over 90 s of standing still (the `stationary_position_only` vector) unless the pedometer drives a ZUPT; the smoother's stop detection removes it in the saved figure. Doppler input does not drift. Twisty position-only tracks under-read (above). Doppler biases below ~0.4 m/s pass the cross-check.

**Position-only recompute off road keeps the forward figure.** Until the corpus retunes `Q_ACCEL`, the server recompute of a track with no Doppler that the road classifier does not accept keeps the forward pass (Server recompute, step 3). Measured on the bench inputs with the smoother's own forward pass, stop hints included (mean of 5 seeds, worst in brackets): canopy switchbacks forward -21.4% [-25.3] against smoothed -31.3%, forest trail -1.2% against -3.1%, and on the open course with two stops +1.0% [+1.5] against -0.1%. The stop hints cost the switchbacks 1.9 points against the plain forward filter's -19.5% (stop detection reads some 12 s legs that double back as stationary) and buy back the stationary drift (+2.3% to +1.0% on the two-stops course), so they are kept. The importers do **not** apply this rule: the Strava fallback in `_shared/strava.ts` (it passes no speed at all), the web FIT fallback in `garmin-fit.ts` and the phone's `embedded_bests.dart` still measure embedded bests on the smoothed cumulative. Their headline distance is the provider's, the estimator only feeds the bests there, they have no road matcher, and a second road definition would drift from `roadDistanceFor`; on every position-only bench row the smoothed figure is the lower of the two, so it gives the slower best, the safe side for a PR, while the forward figure on a road run nobody could classify would give a too-fast one.

## Porting notes

Everything a port needs beyond v1.1. The reference is authoritative where this and it disagree.

### New constants

| Constant | Value | Use |
|---|---|---|
| `GATE_CHI2` | 13.8155 | NIS threshold; accept when `nis <= GATE_CHI2` |
| `GATE_MAX_REJECTS` | 5 | lock-out re-anchor when the consecutive-reject streak becomes `> 5` |
| `R_SCALE_ALPHA` | 0.05 | adaptive R EMA weight |
| `R_SCALE_MIN`, `R_SCALE_MAX` | 1.0, 9.0 | bounds on `rScale`; the sample is also clamped to `[0, R_SCALE_MAX]` |
| `XCHECK_TAU_S` | 60.0 | cross-check EMA time constant |
| `XCHECK_MIN_S` | 120.0 | compared seconds before any verdict |
| `XCHECK_ENTER_ABS_MPS`, `XCHECK_ENTER_REL` | 0.4, 0.15 | distrust threshold `max(abs, rel * |ema_u|)`, strict `>` |
| `XCHECK_EXIT_ABS_MPS`, `XCHECK_EXIT_REL` | 0.2, 0.08 | re-trust threshold, strict `<` |
| `XCHECK_PERSIST_S` | 60.0 | a verdict flips when the condition has held `>=` this long |
| `XCHECK_MAX_SPAN_S` | 5.0 | spans longer than this are not compared |
| `DEBIAS_FULL_MPS`, `DEBIAS_ZERO_MPS` | 0.5, 1.0 | debias weight 1 at `s <= 0.5`, linear to 0 at 1.0, none at `s >= 1.0` |
| `ZUPT_NO_STEP_S` | 6.0 | stationary when `t - lastStepIncreaseT > 6.0` (device-measured value pending) |
| `ZUPT_VEL_SIGMA_MPS` | 0.1 | ZUPT pseudo-measurement variance `0.1^2` |
| `ZUPT_DOPPLER_OVERRIDE_MPS` | 1.0 | trusted Doppler `>=` this cancels a pedometer ZUPT |
| `ZUPT_RELEASE_M` | 40.0 | release when the filtered position has moved `>` this since ZUPT onset |
| `STOP_HALF_WINDOW_S` | 20.0 | stop detection half-window (x `max(1, expectedIntervalS)`) |
| `STOP_MIN_HALF_FIXES` | 3 | fixes required in each half |
| `STOP_SPEED_MPS` | 0.5 | net speed must be `<` this |
| `STOP_RADIUS_M` | 10.0 | RMS radius must be `<` this |
| `SPEC_VERSION` | "1.2" | the fixture's `spec` is `"gps-distance-estimator v1.2"` |

All v1.1 constants are unchanged.

### New and changed signatures (Python names; ports keep their own casing)

- `GpsDistanceEstimator(max_speed_mps=10.0, expected_interval_s=1.0, initial_stride_m=None, record=False)`. `record` is only needed by a port that implements the smoother (it can be an internal constructor).
- `add_fix(t, lat, lng, accuracy_m=None, speed_mps=None, speed_accuracy_mps=None, bearing_deg=None, stopped_hint=False) -> float` (metres credited). `stopped_hint` is new; live recorders always pass false.
- `add_steps(t, cumulative_steps)`, `finish(t)` — unchanged signatures.
- New read-only state: `r_scale` (float, starts 1.0), `rejected_fixes` (int), `zupt_fixes` (int), `doppler_trusted` (bool, starts true).
- `unproject(x, y) -> (lat, lng)` (smoother ports).
- `detect_stops(fixes: [(t, x, y)], expected_interval_s) -> [bool]` (smoother ports).
- `smooth_distance(events, max_speed_mps=10.0, expected_interval_s=1.0, initial_stride_m=None) -> {distance_m, gps_distance_m, step_distance_m, cumulative_m[], positions[], stopped_fixes}`. Events are `fix {t, lat, lng, acc, speed, speedAcc, bearing}` / `steps {t, count}` / `finish {t}`; a port may take a typed event list. `cumulative_m` and `positions` have one entry per input event.

### New estimator state

`rScale = 1`, `rejectedFixes = 0`, `rejectStreak = 0`, `dopplerTrusted = true`, `xcDoppler = xcPos = 0`, `xcTime = 0`, `xcPersistS = 0`, `xcLast = (x, y, t)` (none until the first anchor), `stepsSeen = false`, `lastStepIncreaseT = none`, `zuptReleased = false`, `zuptAnchor = (x, y)` or none, `zuptFixes = 0`. The v1.1 per-axis filters are unchanged; there is no second (shadow) filter. That is about 15 scalars more than v1.1, which a fixed-size port (the Rust `no_std` one) must budget for.

### Doppler helper

`dopplerSpeed(speed, sa_in, maxSpeed) -> (s, sa) or none`: none unless `speed` finite and `0 <= speed <= maxSpeed`; `reported = sa_in finite and > 0`; `sa = reported ? sa_in : 0.5`; none if `sa > 1.5`; if `reported` and `speed < 1.0`: `w = speed <= 0.5 ? 1 : (1.0 - speed) / (1.0 - 0.5)`, `s = sqrt(max(0, speed^2 - w * sa^2))`; else `s = speed`. `sa` (not the debiased speed) feeds the velocity-update variance.

### Order of operations in `add_fix`

1. Invalid `t`, `lat` or `lng` (non-finite or missing): return 0, nothing recorded.
2. First valid fix sets `lat0`, `lng0` (even if it later turns out to be ignored — it cannot be, it is the first).
3. Project with the wrapped longitude difference.
4. `sigma = accuracy if finite and > 0 else 3`; `r_stated = max(sigma, 3)^2`; `r = max(r_stated * rScale, 9)` (using `rScale` before this fix's update).
5. `t <= last t`: return 0 (ignored).
6. `(dop, sa) = dopplerSpeed(...)`.
7. First fix or `t - last t > gapWindow`: commit pending steps if this is a gap (not the first fix), clear the buffer, new axes at `(zx, zy)` with variance `r`, set last t, `xcLast = (zx, zy, t)`, `rejectStreak = 0`, `zuptAnchor = none`; `zupt = stoppedHint or zuptDue(t, dop)` (recorded only); record an anchor; return 0.
8. Clear the pending step buffer; `dt = t - last t`; set last t; predict both axes; snapshot the predicted states.
9. Gate: `yx = zx - px`, `yy = zy - py`, `ax`, `ay` = predicted position variances, `nis = yx^2/(ax + r) + yy^2/(ay + r)`; `accepted = nis <= 13.8155`.
   - Accepted: `rejectStreak = 0`; position update both axes with `r`; `sample = clamp(((yx^2 - ax) + (yy^2 - ay)) / (2 r_stated), 0, 9)`; `rScale = clamp(0.95 rScale + 0.05 sample, 1, 9)`.
   - Rejected: `rejectedFixes += 1`, `rejectStreak += 1`; if `rejectStreak > 5`: `resetPos(zx, r)` / `resetPos(zy, r)` (`p = z`, `a = r`, `b = 0`), `rejectStreak = 0`, `xcLast = (zx, zy, t)`, mark a chain break.
10. Pedometer ZUPT: `pedZupt = zuptDue(t, dop)`, where `zuptDue` is false unless `stepsSeen`, not `zuptReleased`, and `t - lastStepIncreaseT > 6`, and is also false when `dop` is usable, `dopplerTrusted` (its value before step 11) and `dop >= 1.0`. If `pedZupt`: when `zuptAnchor` is none set it to the current filtered `(px, py)`; otherwise `moved = hypot(px - ax0, py - ay0)` and if `moved > 40`: `zuptReleased = true`, `zuptAnchor = none`, `pedZupt = false`, `chord = moved`. If not `pedZupt` (on entry): `zuptAnchor = none`. Then `zupt = stoppedHint or pedZupt`; if `zupt`: `chord = none`, `zuptFixes += 1`, velocity update `0` with variance `0.01` on both axes.
11. Cross-check, only if `accepted`: `(lx, ly, lt) = xcLast`, `span = t - lt`; if `dop` usable, not `zupt`, bearing finite, `dop >= 0.8`, `span <= 5`: `u = ((zx - lx) sin b + (zy - ly) cos b) / span`; if `xcTime == 0` set `xcDoppler = xcPos = dop`, else `alpha = min(1, span / 60)`, `xcDoppler += alpha (dop - xcDoppler)`, `xcPos += alpha (u - xcPos)`; `xcTime += span`; if `xcTime >= 120`: `diff = |xcDoppler - xcPos|`, `ref = |xcPos|`, `flip = trusted ? diff > max(0.4, 0.15 ref) : diff < max(0.2, 0.08 ref)`; `xcPersistS = flip ? xcPersistS + span : 0`; if `xcPersistS >= 60`: toggle `dopplerTrusted`, `xcPersistS = 0`. Then (still only if accepted) `xcLast = (zx, zy, t)`.
12. `useDop = dop if usable and dopplerTrusted else none`. If `useDop`, not `zupt`, bearing finite, `useDop >= 0.4`: velocity update with `useDop * sin(b)`, `useDop * cos(b)`, variance `max(sa, 0.3)^2`.
13. Credit: `chord` if set; else 0 if `zupt`; else `speed = useDop` (floor 0.4) or `hypot(vx, vy)` (floor 0.8), `inc = speed < floor ? 0 : min(speed, maxSpeed) * dt`. Add to `gpsDistance` and to the stride window's metres.
14. Record (smoother ports) and return `inc`.

### `add_steps` change

After the existing early returns (missing / non-finite `t`, missing count, first call, count decreased, `t <= previous step t`), when `d = cumulative - previous > 0`: `stepsSeen = true`, `lastStepIncreaseT = t`, `zuptReleased = false`. The stride logic that follows is unchanged.

### Smoother specifics

- `hasDoppler` = any **accepted** fix whose `speed` is finite (any finite value, even one later rejected as out of range).
- Stop detection runs only when `hasDoppler` is false; the hints are keyed by event index and passed as `stopped_hint`.
- Record per accepted fix: `anchor` (gap / first fix), `chainBreak` (anchor or lock-out), `dt` (0 at an anchor), `pred` (per axis `(p, v, a, b, c)` after predict, none at an anchor), filtered `(p, v, a, b, c)` per axis after all of the fix's updates, `zupt`, `dop` (= `useDop`, or at an anchor `dop` if trusted), `chord`, `stepDistance` after the fix.
- RTS per chain (`[s, e]`, a chain starts at every `chainBreak`), x and y independently, formulas above. Smoothed position = `unproject(ps_x, ps_y)`.
- `cumulative_m[i]`: running sum of credits over accepted fixes up to event `i`, plus the step distance recorded after the latest accepted fix; at a `finish` event the final step distance is used instead.
- `distance_m = sum(credits) + finalStepDistance`; note the last `cumulative_m` equals it only when the last event is the finish.

### What the fixture contains

Top level: `spec` (`"gps-distance-estimator v1.2"`), `reference`, `tolerance_m` (0.001), `position_tolerance_deg` (1e-8, about 1.1 mm), `constants` (every constant above plus v1.1's, by reference name), `scenarios` (27: the 16 v1.1 ones with **unchanged events**, then 11 for v1.2). Each scenario: `name`, `description`, `maxSpeedMps`, `expectedIntervalS`, `initialStrideM`, `events`, and:

- `expected` (forward estimator): `distanceAfterEachEventM` (after every event, including steps and finish), `gpsDistanceM`, `stepDistanceM`, `strideM` (null when none), and new `rejectedFixes`, `zuptFixes` (ints), `rScale` (float), `dopplerTrusted` (bool), all read after the `finish` event.
- `smoothed`: `distanceAfterEachEventM` (`cumulative_m` per event), `distanceM`, `gpsDistanceM`, `stepDistanceM`, `stoppedFixes` (int), `positions` (per event: `[lat, lng]` or null).

v1.1 scenarios whose forward outputs moved: only `walker` (154.83 to 154.79 m, the debias on near-zero Doppler readings). Every other v1.1 forward expectation is unchanged.

### How a port's test must assert it

1. The spec string equals `"gps-distance-estimator v1.2"` and the port's own version constant is `"1.2"`.
2. Every constant the port defines equals the fixture's `constants` entry.
3. For every scenario, replay events through a fresh estimator built from `maxSpeedMps`, `expectedIntervalS`, `initialStrideM` and assert `distance` after each event within `tolerance_m`; after the last event assert `gpsDistanceM`, `stepDistanceM`, `strideM` within `tolerance_m` (null matches null), `rejectedFixes`, `zuptFixes` and `dopplerTrusted` exactly, `rScale` within 1e-6.
4. Smoother ports: call `smoothDistance(events, ...)` and assert each `distanceAfterEachEventM` entry, `distanceM`, `gpsDistanceM`, `stepDistanceM` within `tolerance_m`, `stoppedFixes` exactly, and each `positions` entry null-for-null, else `|lat - lat'| <= position_tolerance_deg` and `|lng - lng'| <= position_tolerance_deg`.
5. Drive the scenario list from the fixture rather than a hard-coded name list, so a new scenario cannot be skipped silently.

Every threshold comparison in the vectors clears its threshold by at least 1.7e-3 relative (checked when the vectors were generated), so float64 ports agree on every branch.
