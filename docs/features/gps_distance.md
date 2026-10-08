# GPS distance estimator (spec v1.1)

How every recorder in the estate turns a stream of GPS fixes into a distance. One algorithm, six ports, one set of golden vectors.

## Why it exists

Until v1, every recorder (Flutter `RunRecorder`, Wear OS `RunRecordingService`, watchOS `WorkoutManager`, the custom-watch firmware) summed the straight-line hop between consecutive raw fixes and dropped hops under a 2-3 m floor. At running pace a 1 Hz fix moves ~2.7 m, the same size as the fix error, so the summed path zig-zags across the true line and every zig-zag adds length. A field report (2026-10-08) had a 3.1 mi course recorded as 3.92 mi (+26%) on a phone while a Garmin watch read ~3.1 mi.

`scripts/gps_distance/bench.py` reproduces it against a synthetic course with realistic, time-correlated phone noise:

| Noise | Old hop-sum | v1 with Doppler | v1 position-only |
|---|---|---|---|
| sigma 3 m, rho 0.9 | +18% | +0.1% | +1.0% |
| sigma 3 m, rho 0.9, two stops | +25% | +0.3% | +2.3% |
| sigma 4 m, rho 0.95, two stops | +45% | +0.3% | +1.9% |

## Algorithm

The reference implementation is [`scripts/gps_distance/reference.py`](../../scripts/gps_distance/reference.py) (stdlib Python, ~150 lines). It is the spec; this page explains it.

1. **Projection.** The first valid fix fixes a local tangent plane: `x = rad(lng - lng0) * R * cos(rad(lat0))`, `y = rad(lat - lat0) * R`, `R = 6371008.8`.
2. **Filter.** Two independent 1-D constant-velocity Kalman filters (x and y), state `[p, v]`, covariance `[[a, b], [b, c]]`, white-acceleration process noise `Q_ACCEL = 0.6 m^2/s^3`. Position measurement variance is `max(accuracy, 3 m)^2`; a missing / non-positive accuracy reads as 3 m.
3. **Doppler.** The chip's own speed (`Position.speed` / `Location.speed` / `CLLocation.speed`, from the carrier Doppler shift) is far more accurate than differentiating positions. It is used when finite, `0 <= speed <= maxSpeed`, and its accuracy (default 0.5 m/s when unreported) is `<= 1.5 m/s`. When a bearing is also present and speed `>= 0.4 m/s`, the speed vector updates the filter's velocity with variance `max(speedAccuracy, 0.3)^2`.
4. **Credit.** Per fix, `speed = Doppler speed` if usable, else `|filtered velocity|`. Below the stationary floor (0.4 m/s with Doppler, 0.8 m/s position-only) the fix credits **zero** — this is what kills red-light drift. Otherwise it credits `min(speed, maxSpeed) * dt`.
5. **Gaps.** `dt > gapWindow` re-anchors the filter at the new fix and credits nothing (the old recorder's `#330` re-anchor semantics). `gapWindow = 10 s x max(1, expectedIntervalS)`, so a recorder that samples sparsely on purpose (the custom watch's 15 s / 60 s GNSS power modes) passes its nominal fix interval and its fixes stay inside the window. A non-increasing timestamp is ignored.
6. **Pedometer.** `addSteps(t, cumulative)` learns a stride while GPS is good (a fix within `2 s x max(1, expectedIntervalS)`): every 50 steps, `stride = metres credited / steps`, accepted if within 0.4-2.5 m, smoothed with an EMA (alpha 0.2). While GPS is not good, steps x learned stride accumulate in a **pending** buffer (capped at `maxSpeed * dt`). If fixes come back inside the gap window the filter integrated the gap itself, so the buffer is discarded; if the gap exceeded it the buffer is committed as `stepDistance`. `finish(t)` commits it when the run ends inside a gap. No learned stride, no step credit. A recorder that starts a fresh estimator for each active stretch (after a pause) passes the previous stretch's stride as `initialStrideM` (ignored outside 0.4-2.5 m), so a gap right after a resume is still filled.
7. **Outputs.** `distance = gpsDistance + stepDistance`, plus `stepDistance` and `stride` for metadata.

The estimator only decides **distance**. The track (the waypoints stored, drawn and route-matched) keeps each recorder's existing movement-gated append rule.

## Waypoint fields

So the server can recompute distance from a stored track with the same Doppler input, each waypoint now carries four optional keys alongside `lat` / `lng` / `elevationMetres` / `timestamp` / `bpm`:

| Key | Unit | Source |
|---|---|---|
| `accuracyMetres` | m | horizontal accuracy |
| `speedMps` | m/s | Doppler speed (omit when invalid / negative) |
| `speedAccuracyMps` | m/s | speed accuracy (omit when not reported) |
| `bearingDeg` | degrees clockwise from north | course over ground (omit when invalid) |

Old tracks have none of them and recompute through the position-only path.

## Ports

| Port | Path |
|---|---|
| Reference (Python) | `scripts/gps_distance/reference.py` |
| Dart (phone) | `packages/run_recorder/lib/src/gps_distance_estimator.dart` |
| TypeScript (web, canonical pair) | `apps/web/src/lib/runs/gps_distance.ts` |
| Kotlin (Wear OS) | `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/recording/GpsDistanceEstimator.kt` |
| Swift (watchOS) | `apps/watch_ios/WatchApp/GpsDistanceEstimator.swift` |
| Rust `no_std` (custom watch) | `apps/custom_watch/core/src/gps_distance.rs` |
| Go (server recompute) | `apps/job_worker/internal/gpsdistance/` |

Every port has a test that replays [`fixtures/gps_distance_vectors.json`](../../fixtures/gps_distance_vectors.json) and asserts the distance after **every** event to `tolerance_m` (1e-3 m). Changing the algorithm means editing `reference.py`, regenerating with `python3 -I scripts/gps_distance/gen_vectors.py fixtures/gps_distance_vectors.json`, and updating every port in the same change, bumping the spec version.

## Server recompute

Runs recorded before v1 keep their inflated hop-sum distance until something re-derives it. The server can, from the stored track:

1. **UI.** On `/runs/[id]` the owner sees **Recalculate distance** under the key stats when `canRecomputeDistance` (`apps/web/src/lib/runs/distance_recompute.ts`) holds: they own the run, it has a `track_url`, its `source` is `app` or `watch` (an import's distance belongs to the system that recorded it), `metadata.distance_source` is not `pedometer` (no GPS to recompute from), and `metadata.distance_estimator` is not already `kalman_v1`. The action opens a ConfirmDialog saying the distance will be recomputed with the improved GPS filter and the original kept, then calls the RPC. Success shows "Recalculating — refresh in a minute" and hides the action; a refusal (not the owner, no track) or any other failure is shown as an error toast and the action stays offered.
2. **RPC.** `request_distance_recompute(p_run_id uuid) returns void` (migration `20270716000001`) is SECURITY DEFINER, `authenticated`-only, raises `42501` unless the caller owns the run and `22000` when it has no track, and inserts a `distance_recompute` job with payload `{run_id, user_id}`. A partial unique index (`jobs_dedupe_distance_recompute`) makes a second request while one is queued or running a no-op. See [api_database.md](../backend/api_database.md).
3. **Job.** The Go worker (`apps/job_worker/internal/gpsdistance/`) downloads the track, replays its waypoints through the estimator (the Doppler path when the waypoints carry `speedMps` and friends, position-only otherwise), and rewrites `runs.distance_m`. It skips sources other than `app` / `watch`.
4. **Metadata.** The worker writes `distance_estimator = "kalman_v1"` and `distance_recomputed_at`, and copies the recorder's figure into `distance_recorded_m` (only when absent, so a second recompute never loses the original). The page shows it as "Originally recorded: X" in the viewer's unit. All keys are registered in [metadata.md § Distance estimator](../backend/metadata.md).

## Tuning

The constants are in the fixture's `constants` block. Do not tune a port independently — the vectors will fail, which is the point.

Known limits: position-only input still drifts ~15 m over 90 s of standing still (the `stationary_position_only` vector); Doppler input does not. A route with tight switchbacks under heavy canopy is the weakest case for any filter and has not been measured against ground truth.
