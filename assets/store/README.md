# Store screenshots

The Play and App Store screenshots are made from the real app on seeded demo data, not by hand (issue #1375). There are two stages: CI captures the app's screens, and a renderer composes the captioned panels from those captures.

## 1. Capture (CI, Android emulator)

`.github/workflows/store-screenshots.yml` runs on demand (Actions → Store screenshots → Run workflow) and on any PR that touches this pipeline. It does the following:

1. Starts the local Supabase stack (`.github/actions/start-supabase`) and loads `demo/store_demo_seed.sql`. That file creates a dedicated demo account (`store-demo@threkir.test`, "Sam Rivera") on the free tier with health-data consent and no sex set, an active plan for the fictional Wrenfield Half Marathon and a coach thread on that plan. Free, because the listing says the analysis is not locked, so nothing in it may come from a paid state; consent, because per-point heart rate is kept only with it. The plan is what the app's generator writes for that profile and a 1:45:00 half with no recent 5K (a female profile would take a 3% slower pace calibration): VDOT 42.64 (`vdotFromRace`), tempo 4:50/km (Daniels' threshold pace at that VDOT) and the other paces `resolveTrainingPaces` gives for that goal. Its latest quality session before today is a 10K tune-up. Every date is relative to the run day, so a capture made on any day shows today in week 6 of 12 with the race six weeks out. The plan's Monday-to-Saturday sessions are rotated so that today is always the tempo (Sunday stays the long run, and on a Sunday today is the long run), because the Today panel's caption promises a run one tap away and a rest day would contradict it. `demoSlotFor` in `demo_data.dart` is the same rotation. No session is ticked off by hand: the app pushes a run for every past session and the server's run-to-workout matcher links each one, as it does for a real runner. A hand tick on top of a run counts the session twice in the week's distance.
2. Builds and starts the Go job worker (`apps/job_worker`) against the stack. It is there for one job: the hero run's `map_match`. Until that row leaves `pending`, the run map carries a "Snapping to roads…" pill. Without `OSRM_URL` the worker matches by passthrough, so the row settles as `matched` with no OSRM graph. Its log is uploaded as `job-worker-log`.
3. Boots an API 34 Pixel 6 emulator and runs `apps/mobile_android/integration_test/store/store_screenshots_capture.dart` with `flutter drive --profile` through `capture.sh`, which also works by hand against any booted device and local stack. The suite does the following:
   - writes six weeks of base running and the plan's runs into the device's run store (`demo_data.dart`). Without the base, five weeks of history from nothing reads as heavy fatigue on Today's readiness line. Two runs are written by hand rather than from the session's target:
     - the hero run, the most recent run that is not a long run: one counter-clockwise lap of Central Park's full loop of drives from Columbus Circle (6.1 miles; 9.76 km traced), over a real line and real elevations (`hero_route.dart`, below). It is run at an even effort that tires a little, so raw pace fades up Harlem Hill in the sixth km while the grade-adjusted pace holds, and it carries a heart rate on every point;
     - the 10K tune-up, raced in 47:50, which the Race-time predictor anchors on, so its Half row reads 1:45:19. The coach thread quotes that tune-up and a 1:45 to 1:46 half.

     `apps/mobile_android/test/store_demo_hero_run_test.dart` pins what the app makes of both, through the run detail's and the predictor's own helpers: a positive raw split with an even grade-adjusted one, the slowest km being the climb and at least 30 s/km slower raw than grade-adjusted, heart rate in all five zones, and the predicted half on every weekday a capture can run.
   - starts the real `main()`, which signs in through the app's own dev auto-login (loopback only)
   - waits for every seeded run to reach the server (and fails if the device holds a different number of runs), then for the hero run's map-match row to settle as `matched`, and for Today to show today's session with no "missed" prompt, which it does once the plan re-reads after the server linked the runs
   - captures `today`, `record` (the run detail, failing if any map-match pill is still on the map), `train` (the plan, in the light theme) and `coach`. The coach capture waits for the seeded thread's last question to be on screen, which it is only once the Coach has scrolled the thread to its latest exchange; that scroll waits for the frame that lays the thread out (`ChatStickToBottom`), so the capture no longer depends on how quickly the local stack answers
4. Uploads the raw captures (`store-screenshots-raw`). A second job then renders the panels and uploads them as `store-screenshots-panels`.

Nothing in the capture reaches production. The stack and the job worker are local. `WEB_BASE_URL` points at a loopback port where nothing listens, and the only outside request is for MapTiler map tiles. Those use the `PUBLIC_MAPTILER_KEY` secret, and a fork PR without it falls back to OSM tiles.

Every place the suite depends on the app's layout is in `store_selectors.dart`. The hero screens are pushed with the app's own constructors, so a renamed screen or a changed constructor fails `dart analyze` rather than the emulator run. The suite is not a `*_test.dart` file, so the backend-free `mobile-android-e2e` job never loads it.

### The hero run's route

`apps/mobile_android/integration_test/store/hero_route.dart` (and the iOS twin) is generated by `python3 -I assets/store/demo/hero_route.py`, which needs the network and takes a few minutes. It traces the loop over the OpenStreetMap ways named East, West and Center Drive (via the Overpass API, ODbL) and samples USGS 3DEP elevations every 20 m (Elevation Point Query Service, public domain, 1 m lidar in the park). `demo_data.dart` smooths the elevations, since the bare-earth model drops the drive where it crosses an arch, then times the run and puts the heart rate on it. Re-run the script only to move the route on purpose; its diff shows what moved upstream.

## 2. Compose (`gen-store-screenshots.sh`)

```
bash assets/store/gen-store-screenshots.sh --captures <dir of raw PNGs> --out <dir>
```

The script fills `templates/panel.svg` (the headline and subline over the coral-to-violet brand ramp, then the enlarged screen in a phone outline that runs off the bottom edge) once per panel, target size and locale, and renders it with Inkscape in Manrope from `packages/ui_kit/fonts`. It writes `<out>/<locale>/<target>/<NN>-<panel>.png`:

| Target | Size | Store slot |
|---|---|---|
| `play-phone` | 1080 x 1920 | Play Console → Store listing → Phone screenshots |
| `appstore-6.9` | 1320 x 2868 | App Store Connect → 6.9" Display |

Before the script exits 0, it checks every PNG for the exact size and for 8-bit RGB with no alpha, which is what Play's "24-bit PNG" means. It needs `inkscape` (1.2 or later, for `--export-png-color-mode`) and `python3`. It uses nothing else, and it runs the same on a Mac (Homebrew `inkscape`) as on the CI runner (`ubuntu-24.04`'s packaged Inkscape).

- **Panel order and captures:** `panels.json`. The order there is the listing order.
- **Captions:** `captions/<locale>.json`, one object per panel with `headline` (a list of lines, broken by hand because SVG text does not wrap) and `subline`. To add a locale, add a file; the script renders every locale it finds and fails on any panel a locale leaves out. Only `en` exists today.
- **Layout:** the fractions at the top of `render_panels.py`. They are proportions of the panel width or height, so the two targets stay consistent.

## Release notes

`whats-new-en.txt` is the Play "What's new" text for the release that ships the new navigation (it replaces "Threkir is now on Google Play."). It is at most 500 characters. It goes in the GitHub Release body's `## What's New` section, which `release-android.yml` sends to Play (see `apps/mobile_android/deployment.md`).

## Uploading (owner)

Download `store-screenshots-panels` from the workflow run and look through every panel. Then upload `en/play-phone/*` in Play Console and `en/appstore-6.9/*` in App Store Connect, in file-name order. Store uploads are manual. No workflow holds store-listing write access.
