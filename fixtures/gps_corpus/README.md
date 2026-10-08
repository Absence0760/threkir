# GPS ground-truth corpus

Real tracks recorded on courses whose length is known independently of any GPS
device, replayed through the reference estimator
(`scripts/gps_distance/reference.py`) on every PR. This is the corpus issue
#1090 item 2 asks for: everything the estimator's constants were tuned against
until now came from synthetic noise (`scripts/gps_distance/bench.py`).

```
python3 -I scripts/gps_distance/replay_corpus.py              # table, exit 1 if any entry is outside budget
python3 -I scripts/gps_distance/replay_corpus.py --json       # the same numbers, machine-readable
python3 -I scripts/gps_distance/replay_corpus.py <other_dir>  # replay a private corpus that is not committed
```

CI runs the first form in the `watch-wire-vectors` job.

## Ground truth is a measured course, never a watch

Sport watches miss by 3–6% on average and under-read by up to 9% in forest and
between buildings (Gilgen-Ammann et al. 2020), so "matches the Garmin" is not a
pass. `known_distance_m` must come from one of:

- a running track's lane 1 (400 m per lap, measured 0.30 m outside the kerb)
- a certified road course (World Athletics / USATF / AIMS measured)
- a calibrated measuring wheel or a surveyor's figure for the route you ran

Errors are reported **signed**. A heavy filter cuts corners, so under-counting
under trees or on track bends shows as a negative number; it is as much a
failure as the GPS-noise over-count the filter exists to remove.

## Format

One entry is two files side by side: the track and `<name>.manifest.json`.

| Manifest key | Required | Meaning |
|---|---|---|
| `id` | yes | Stable name, shown in the report |
| `track_file` | yes | The track, relative to this directory |
| `format` | no | `threkir_json`, `gpx` or `fit`; inferred from the extension (`.json` / `.json.gz` / `.gpx` / `.fit`) |
| `known_distance_m` | yes | The course's true length for what was run (laps × lap length, start-to-finish on a road course) |
| `distance_source` | yes | How that length is known, in words: "lane 1, 6 laps", "USATF-certified 5K", "measuring wheel, 2026-10-12" |
| `course_type` | yes | `track`, `road`, `trail` or `urban` |
| `device` | yes | The recording device and app version, e.g. "Pixel 8, Threkir mobile_android 1.42.0" |
| `platform` | yes | `android`, `ios`, `wear_os`, `watchos`, `garmin`, `custom_watch` or `synthetic` |
| `activity_type` | no | Picks the speed ceiling, as in the app; `run` when absent |
| `expected_interval_s` | no | Overrides the median fix interval |
| `error_budget_pct` | yes | Allowed \|signed error\|, in percent of `known_distance_m` |
| `synthetic` | no | `true` only for generated entries; printed in the report |
| `notes` | no | Weather, tree cover, where the phone was carried, anything odd |

Track formats:

- **`threkir_json`** — the stored track exactly as the app saved it: the
  `tracks/<run_id>.json.gz` entry of a Threkir data export, or the
  `{user_id}/{run_id}.json.gz` object in the `runs` bucket. The **preferred**
  format, because it carries the Doppler keys (`speedMps`, `speedAccuracyMps`,
  `bearingDeg`, `accuracyMetres`) the estimator fuses. A GPX export drops them
  and replays through the position-only path, which is not what the phone ran.
- **`gpx`** — `trkpt` with `<time>`; position only.
- **`fit`** — record messages; position only goes to the estimator (a Garmin's
  `record.speed` is its own filtered speed, not raw Doppler), and the last
  `record.distance` is printed in the `device` column for comparison.

## Columns the report prints

`saved` (the smoothed figure a saved run stores, or the forward figure when the
reference has no smoother) is what the budget is checked against. `forward` is
the live-screen figure, `hop` the raw fix-to-fix sum, `device` the file's own
distance. `NIS` is the mean normalised innovation squared of accepted fixes —
2.0 for a consistent filter, persistently higher means `R` or `Q_ACCEL` is too
small for that course, lower means too large. `C` is the lag-1 autocorrelation
of fix-minus-smoothed residuals, an estimate of Ranacher et al.'s (2015) error
autocorrelation. NEES needs the true state at every fix, which no real entry
has; `nees_hook` in the script is where a generator that writes truth adds it.

Tuning uses these, per `course_type` and `activity_type`. Any constant change
still goes through `reference.py`, regenerates `fixtures/gps_distance_vectors.json`
and bumps the spec version (`docs/features/gps_distance.md`); the corpus budget
is a floor, not the tuning target.

## The one synthetic entry

`track_400m_lane1_x6.synthetic.*` is generated, not recorded:
`python3 -I scripts/gps_distance/gen_synthetic_corpus.py fixtures/gps_corpus`
writes it deterministically (six laps of lane 1 at 4:20/km, 1 Hz, AR(1) position
error with σ 3 m and lag-1 correlation 0.95, one 25 m multipath spike). It
proves the harness runs in CI. It says nothing about real GPS, and it is
removed — or kept only as a harness smoke test — once real entries land.

## What the owner needs to record

Each run below becomes one entry. Record it on the phone build that ships the
v1.1+ estimator; keep the phone where you normally carry it and note that in
`notes`.

1. **The field-report course (#922 § 11).** Run the same 3.1 mi course with the
   phone and the Garmin together. Export the Threkir track (web `/settings/account`
   → the full account archive, then take `tracks/<run_id>.json.gz` from it) and the
   Garmin FIT (Garmin Connect → the activity → ⚙ → Export Original). If the
   course is not measured, the Garmin figure is a comparison, not the truth —
   set `known_distance_m` only from a measurement and say which in
   `distance_source`. Course type `road` or `urban`.
2. **A 400 m track, lane 1, several laps** (6–10). `known_distance_m` = laps ×
   400. Run lane 1 throughout, start and stop on the same line. Course type
   `track`. This is where filters over-read most (Gilgen-Ammann 2020) and where
   heavy smoothing cuts the bends.
3. **A measured road loop.** A certified course, or a loop you walked with a
   calibrated measuring wheel. Course type `road` (open sky) or `urban` (tall
   buildings).
4. **A tree-covered trail** with a known length (a measured or published trail
   distance you trust, with its source). Course type `trail`. This is the
   under-count check.

If possible record each on both an Android phone and an iPhone — Android
records a fix every 5 s by default and iOS every second at reduced accuracy
(#1090 research findings 1–2), and those are different noise regimes. Set an
`error_budget_pct` you would accept as a runner (2% on the track and the road
loop is a reasonable start), commit the pair, and run the replay.

## Item 6 — fused provider vs raw GPS on Android

The same corpus answers #1090 item 6. On an Android phone, record the track
and road-loop runs twice: once on the normal build (fused provider) and once on
a build with `forceLocationManager: true` (raw `GPS_PROVIDER`), each as its own
entry with the provider named in `device`. Compare their `saved` error, their
`NIS` and `C` (a fused track that already smooths shows lower `C` residuals and
lower NIS — double smoothing), and the battery each used over the run (Settings
→ Battery → app usage, noted in `notes`). Dual-frequency L1+L5 cannot be
switched on through geolocator; note per device whether the phone has it.
