# Store screenshots

The Play and App Store screenshots are made from the real app on seeded demo data, not by hand (issue #1375). There are two stages: CI captures the app's screens, and a renderer composes the captioned panels from those captures.

## 1. Capture (CI: Android emulator and iOS simulator)

`.github/workflows/store-screenshots.yml` runs on demand (Actions → Store screenshots → Run workflow) and on any PR that touches this pipeline. Its `capture` job makes the Play set on an Android emulator and its `capture-ios` job makes the App Store set on an iOS simulator, from the same suite. The Android job does the following:

1. Starts the local Supabase stack (`.github/actions/start-supabase`) and loads `demo/store_demo_seed.sql`. That file creates a dedicated demo account (`store-demo@threkir.test`, "Sam Rivera") on the free tier with health-data consent and no sex set, an active plan for the fictional Wrenfield Half Marathon and a coach thread on that plan. Free, because the listing says the analysis is not locked, so nothing in it may come from a paid state; consent, because per-point heart rate is kept only with it. The plan is what the app's generator writes for that profile and a 1:45:00 half with no recent 5K (a female profile would take a 3% slower pace calibration): VDOT 42.64 (`vdotFromRace`), tempo 4:50/km (Daniels' threshold pace at that VDOT) and the other paces `resolveTrainingPaces` gives for that goal. Its latest quality session before today is a 10K tune-up. Every date is relative to the run day, so a capture made on any day shows today in week 6 of 12 with the race six weeks out. The plan's Monday-to-Saturday sessions are rotated so that today is always the tempo (Sunday stays the long run, and on a Sunday today is the long run), because the Today panel's caption promises a run one tap away and a rest day would contradict it. `demoSlotFor` in `demo_data.dart` is the same rotation. No session is ticked off by hand: the app pushes a run for every past session and the server's run-to-workout matcher links each one, as it does for a real runner. A hand tick on top of a run counts the session twice in the week's distance.
2. Boots an API 34 Pixel 6 emulator and runs `apps/mobile_android/integration_test/store/store_screenshots_capture.dart` with `flutter drive --profile` through `capture.sh`, which also works by hand against any booted device and local stack. The suite does the following:
   - writes six weeks of base running and the plan's runs into the device's run store (`demo_data.dart`). Without the base, five weeks of history from nothing reads as heavy fatigue on Today's readiness line. Two runs are written by hand rather than from the session's target:
     - the hero run, the most recent run that is not a long run: one counter-clockwise lap of Central Park's full loop of drives from Columbus Circle (6.1 miles; 9.76 km traced), over a real line and real elevations (`hero_route.dart`, below). It is run at an even effort that tires a little, so raw pace fades up Harlem Hill in the sixth km while the grade-adjusted pace holds, and it carries a heart rate on every point;
     - the 10K tune-up, raced in 47:50, which the Race-time predictor anchors on, so its Half row reads 1:45:19. The coach thread quotes that tune-up and a 1:45 to 1:46 half.

     `apps/mobile_android/test/store_demo_hero_run_test.dart` pins what the app makes of both, through the run detail's and the predictor's own helpers: a positive raw split with an even grade-adjusted one, the slowest km being the climb and at least 30 s/km slower raw than grade-adjusted, heart rate in all five zones, and the predicted half on every weekday a capture can run.
   - starts the real `main()`, which signs in through the app's own dev auto-login (loopback only)
   - waits for every seeded run to reach the server (and fails if the device holds a different number of runs), and for Today to show today's session with no "missed" prompt, which it does once the plan re-reads after the server linked the runs
   - captures what the panels crop (below), and writes `bounds.json` and `numbers.json` beside the PNGs
3. Uploads the raw captures (`store-screenshots-raw`). The compose job then renders the panels and uploads them as `store-screenshots-panels`.

The `capture-ios` job runs the same suite from `apps/mobile_ios` (the byte-identical twin) through `STORE_APP=mobile_ios bash assets/store/capture.sh <udid> <dir>`, in debug mode because a simulator cannot run a profile build. It boots the newest iPhone Pro Max simulator the image offers, since every Pro Max since the 16 is the 6.9" class (1320 x 2868, 440 pt at 3x); the suite fails on any other size. GitHub's macOS images have no Docker, so the job starts one in a Colima VM on the Intel image (`macos-15-intel`; the Apple-silicon runners cannot nest a VM) and runs `supabase start` without the services the capture never reaches (the edge runtime, the log pipeline, Studio and postgres-meta, imgproxy, the pooler). It waits for the containers to be healthy itself, for up to 6 minutes, rather than through the CLI, which removes the containers on a timeout before anything is logged; on failure the step prints each unhealthy container's health probe and log. It uploads `store-screenshots-raw-ios`. If that job fails, compose still renders and uploads the Play set and then fails, naming the missing App Store set.

### What the suite captures

Each capture is the pushed screen's own layer (`RenderRepaintBoundary.toImage`, in `integration_test/store/store_capture_kit.dart`), not a platform screenshot. So the Android and iOS captures are made the same way, carry no status bar, navigation bar or home indicator, and can be laid out at a width the device doesn't have:

| Capture | Screen | Width, pixel ratio | Theme | Sections |
|---|---|---|---|---|
| `run-zones` | run detail, scrolled to Heart rate zones | 320 dp at 3.0 (Play) / 3.666 (App Store) | dark | `hr-zones` |
| `run-splits` | run detail, scrolled to Splits | 320 dp, same | dark | `splits-title`, `pacing-card`, `gap-header`, `split-row-<n>`, `splits-hint` |
| `run-pacing` | the same, at text scale 1.5 | 320 dp, same | dark | `splits-title`, `pacing-card`, `gap-header`, `split-row-1`, `split-row-2` |
| `progress` | Progress, scrolled to the Race-time predictor | 320 dp, same | light | `predictor-card`, `predictor-row-{5k,10k,half,marathon}` |
| `plan` | plan detail with "Plan progress" open | the device's width and ratio | light | `plan-header`, `plan-week`, `plan-progress` |
| `coach` | the Coach on the seeded thread | the device's width and ratio | dark | `coach-context`, `coach-last-exchange` |

The 320 dp captures set the test view's size and pixel ratio, so the app lays itself out at that width and the column fills the panel card pixel for pixel (960 px for Play, 1173 px for the App Store). The plan capture's view is 1600 dp tall so the "Plan progress" card is on screen with the header; the panel crops sections, so the height never shows.

Each section is a keyed widget in the app (`run-detail-*` in `run_detail_screen.dart`, `race-predictor-*` in `race_predictor_card.dart`, `planDetailHeroCard` and `plan-disclosure-progress` in `plan_detail_screen.dart`, `coach-context-strip` in `coach_screen.dart`), or a widget type, all listed in `store_selectors.dart`. The coach's last exchange runs from the bubble holding the seed's last question to the end of the answer bubble below it, above the answer's action icons. A section that is missing, runs off the screen or is clipped by its list fails the capture with its name.

The coach's usage banner (`coach-limit-banner`) and the typing indicator are never shown in a crop. If either is on screen, the suite records its rect under `forbidden` in `bounds.json`, fails if it overlaps a section, and the renderer refuses any crop that reaches it. That means it is cropped out, as the spec asks, and never hidden in the app. The seeded thread has no timestamps for a "now" to show in.

`numbers.json` is read off the screens as they are captured. Each display string is the text the screen shows, and each is recomputed through the helpers that screen calls: `computeSplitDurations`, `gradeAdjustedSplitPaces` and `analysePacing` for the splits and pacing, `predictRaceLadder` over `qualifyingRuns` for the predictor, and the plan row behind the header card. A mismatch fails the capture. The helpers also supply what the screen doesn't print: each km's climb, the pacing verdicts and the confidence grades. The tier is the coach's own `is_pro` read. The driver (`store_screenshots_driver.dart`) writes the PNGs and both JSON files from the suite's report data, and only when the run passed.

`test/store_capture_kit_test.dart` checks, without a device, the arithmetic from widget box to capture pixels, the colour sampling, and the forbidden-widget and clipped-section failures.

Nothing in the capture reaches production. The stack is local. `WEB_BASE_URL` points at a loopback port where nothing listens, and the only outside request is for MapTiler map tiles. Those use the `PUBLIC_MAPTILER_KEY` secret, and a fork PR without it falls back to OSM tiles.

Every place the suite depends on the app's layout is in `store_selectors.dart`. The hero screens are pushed with the app's own constructors, so a renamed screen or a changed constructor fails `dart analyze` rather than the emulator run. The suite is not a `*_test.dart` file, so the backend-free `mobile-android-e2e` job never loads it.

### The hero run's route

`apps/mobile_android/integration_test/store/hero_route.dart` (and the iOS twin) is generated by `python3 -I assets/store/demo/hero_route.py`, which needs the network and takes a few minutes. It traces the loop over the OpenStreetMap ways named East, West and Center Drive (via the Overpass API, ODbL) and samples USGS 3DEP elevations every 20 m (Elevation Point Query Service, public domain, 1 m lidar in the park). `demo_data.dart` smooths the elevations, since the bare-earth model drops the drive where it crosses an arch, then times the run and puts the heart rate on it. Re-run the script only to move the route on purpose; its diff shows what moved upstream.

## 2. Compose (`gen-store-screenshots.sh`)

```
bash assets/store/gen-store-screenshots.sh --captures play-phone=<dir> [--captures appstore-6.9=<dir>] --out <dir>
```

`render_panels.py` builds each panel as SVG and renders it with Inkscape in Manrope from `packages/ui_kit/fonts`. A panel is a ground (dark, ramp or light), a left-aligned headline at 0.104 of the panel width with an optional kicker and accent-coloured numbers, and below it a rounded card of cropped screen sections with a lift shadow. There is no phone outline. Content longer than the card fades into the screen colour at its bottom. The layout constants at the top of `render_panels.py` are Play pixels and scale with the panel width. The style frames for concept C (#1375) are the reference.

It writes `<out>/<locale>/<target>/<NN>-<panel>.png`, plus `<out>/<locale>/play-phone-variant-b/` for the Play store listing experiment. That folder holds the whole set with the alternate first panel (`slowest-km-alt`, "Your slowest km wasn’t slow."), so it can be uploaded in order as variant B. It also writes `<out>/report.json` with each panel's headline size, card box and worst text contrast.

| Target | Size | Captured on | Store slot |
|---|---|---|---|
| `play-phone` | 1080 x 1920 | Android suite | Play Console → Store listing → Phone screenshots |
| `appstore-6.9` | 1320 x 2868 | iOS suite | App Store Connect → 6.9" Display |

The App Store set must come from the iOS captures, since an Android screen in an App Store listing breaks Apple's rule 2.3.10. Without `--captures appstore-6.9=<dir>` the render fails. `--appstore-from-android` draws that set from the Android captures for a local look only, and prints a warning that it must not be uploaded. The workflow never passes it: it passes the iOS job's captures, or renders `--target play-phone` alone when that job failed.

Before the script exits 0, it checks every PNG for the exact size and for 8-bit RGB with no alpha, which is what Play's "24-bit PNG" means. It needs `inkscape` (1.2 or later, for `--export-png-color-mode`) and `python3`, and nothing else. It runs the same on a Mac (Homebrew `inkscape`) as on the CI runner (`ubuntu-24.04`'s packaged Inkscape).

### What it refuses to render

- **A typed number in a caption.** Every number comes from a `numbers.json` placeholder.
- **A number that isn't on the panel's own screen.** Each panel's `numbers` list names the placeholders it may show.
- **A claim the data doesn't support.** The panel's `claims` (plus the top-level `claims`) are checked in `store_numbers.py`:
  - `free_tier`: every capture is on a free account.
  - `slowest_km_uphill`: the slowest km has a net climb.
  - `slowest_gap_at_least_30`: raw minus grade-adjusted is at least 30 s/km on that km.
  - `slowest_gap_near_median`: that km's grade-adjusted pace is within 3 s/km of the median.
  - `raw_positive_gap_even`: raw pacing is a positive split and grade-adjusted is even.
  - `zones_all_five`: the heart rate reaches all five zones.
  - `predicted_half_is_goal`: the Half rung shows the goal's h:mm, from :00 to :29.
  - `plan_is_half`: the plan's race is a half marathon.
  - `vdot_matches_goal`: the VDOT chip equals `vdotFromRace` of the goal.
- **A store listing rule broken in a headline or kicker.** No Free, Best, Top, New, Sale, call to action, price, other app or platform, miles or feet, "real" or "true" pace, all-caps word or emoji.
- **A line that only fits below 0.094 of the panel width.** Rewrite the line instead.
- **Text under 4.5:1 against its ground.** This is measured from the ground's own gradients.
- **A capture in the wrong theme, or a run-detail capture that isn't 320 dp wide.**

### Captions (`captions/<locale>.json`)

Each panel has:

- `headline`: a list of lines, broken by hand.
- `kicker` (optional): the small line above the headline.
- `accent` (optional): substrings of the headline drawn in the ground's accent colour.
- `subline` (optional).

Numbers are written as placeholders: `{slowest.km}`, `{slowest.raw}`, `{slowest.gap}`, `{plan.weeks}`, `{plan.goal}`, `{plan.goal_hm}`, `{plan.vdot}`, `{predictor.half}` and `{predictor.half_hm}`. An `_hm` value is h:mm, truncated. To add a locale, add a file. The script renders every locale it finds and fails on any panel a locale leaves out.

### Panels (`panels.json`)

The order of `panels` is the listing order. Each panel has:

- `ground` and `theme` (the capture's app theme).
- `numbers` and `claims`.
- `crops`: a list, or a map of lists keyed by target.

Each crop takes `capture`, plus `from` and `to` section names. The crop runs from the top of `from` to the bottom of `to`, at the capture's full width. Optional keys:

- `pad_top_dp` / `pad_bottom_dp`: a pad stops at a neighbouring section.
- `gap_px`: a visible gap before this crop.
- `lift`: draw the section as a card lifted over the panel card.
- `window`: on a run longer than `max` km, keep only the split rows from `before` the slowest km to `after` it.
- `optional`: skip the crop when its sections are missing.
- `rect`: `[x, y, w, h]` in capture pixels, or a map keyed by target. This is the fallback when the bounds don't name the sections.

Each panel may also set:

- `callout`: rebuilds one row from `numbers.json` at `scale` times its size, in place of the captured row. `split` is the slowest km (2.5x, with no duration lane). `predictor` is the Half rung (1.6x, all four columns).
- `dim`: section-name prefixes covered by a 55% scrim of the screen colour, so the lifted callout is the brightest thing at thumbnail size.
- `valign: "center"`: centres a short card in its space instead of leaving bare ground under it.
- `fade: "always"`.

A card that still leaves more than 200 px of bare ground is named in the render's output and in `report.json`. Fix that with a narrower capture, not in the renderer.

### What the capture suite writes beside its PNGs

`bounds.json` says where each section sits in each capture, in capture pixels:

```json
{
  "schema": 1,
  "captures": {
    "run-splits": {
      "file": "run-splits.png", "theme": "dark", "dpr": 3.0,
      "sections": { "gap-header": [0, 312, 960, 66], "split-row-1": [0, 378, 960, 96] },
      "colours": { "pacing-card": "#36323F" }
    }
  }
}
```

- **`dpr`** converts dp pads to pixels. **`size`** is the PNG's own size, for reading the file by eye.
- **`forbidden`** (optional) gives the rect of a widget that must never show in a crop, such as `coach-limit-banner`. A crop that overlaps one is refused, and a pad stops at one as it does at a neighbouring section.
- **`colours`** (optional) gives the fill behind a section that becomes a callout or a lift: `pacing-card` and `predictor-row-half`. Without it the renderer uses the theme's container colour (for a lift) or the page background (for a callout).
- **Captures and sections the panels use:**
  - `run-splits`: `splits-title`, `pacing-card`, `gap-header`, `split-row-<n>` for every km, and `splits-hint`.
  - `run-zones`: `hr-zones`.
  - `run-pacing`: captured at text scale 1.5, with `splits-title`, `pacing-card`, `gap-header`, `split-row-1` and `split-row-2`.
  - `progress`: `predictor-card` and `predictor-row-{5k,10k,half,marathon}`.
  - `plan`: `plan-header`, `plan-week`, and optionally `plan-progress`, which is "Plan progress" expanded.
  - `coach`: `coach-context`, which is the chip row, and `coach-last-exchange`, from the question bubble to the end of the answer bubble.
- **Width:** the run-detail and progress captures are 320 dp wide.

`numbers.json` holds the numbers as the app formats them on screen, from the code the screens use:

```json
{
  "schema": 1,
  "tier": "free",
  "labels": { "grade_adj": "Grade-adj." },
  "run": {
    "splits": [ { "km": 1, "raw": "5:14", "gap": "5:10", "elev_delta_m": 1.0 } ],
    "slowest_km": 6,
    "pacing": {
      "raw": { "first": "5:10", "second": "5:21", "delta_s": 11, "verdict": "positive" },
      "grade_adjusted": { "delta_s": 1, "verdict": "even" }
    },
    "hr": { "avg": 149, "min": 116, "max": 181 },
    "zones": [ { "zone": 1, "time": "2m 40s", "pct": 6 } ]
  },
  "predictor": {
    "anchor": { "distance": "10 km", "time": "49:58" },
    "rungs": {
      "5k": { "distance": "5 km", "time": "23:58", "pace": "4:48/km", "confidence": "high", "confidence_label": "High" },
      "10k": { "...": "..." }, "half": { "...": "..." }, "marathon": { "...": "..." }
    }
  },
  "plan": { "weeks": 12, "goal": "1:45:00", "goal_distance_m": 21097.5, "vdot": "42.6", "race_name": "..." }
}
```

- **`splits`** lists every whole km in order. `elev_delta_m` is the net climb inside that km.
- **`slowest_km`** must be the km with the slowest raw split.
- **Verdicts** are `analysePacing`'s: `negative`, `even` or `positive`.
- **`confidence`** is `high`, `moderate` or `low`. `confidence_label` is the chip's own text.
- **`labels`** and the display strings are in the capture locale.

`test_fixtures/` holds a complete pair of these files.

### Tests

```
python3 -m unittest discover -s assets/store -p 'test_*.py' -v
```

`test_render_panels.py` covers:

- the claims and placeholders;
- the store-rule lint;
- the layout numbers from the spec;
- the split window, the fallback rects, and the theme and width guards;
- the missing-iOS-captures failure;
- one full Inkscape render from the fixtures, skipped where Inkscape isn't installed.

The workflow's `renderer-tests` job runs it on every PR that touches this directory.

## Release notes

`whats-new-en.txt` is the Play "What's new" text for the release that ships the new navigation (it replaces "Threkir is now on Google Play."). It is at most 500 characters. It goes in the GitHub Release body's `## What's New` section, which `release-android.yml` sends to Play (see `apps/mobile_android/deployment.md`).

## Uploading (owner)

Download `store-screenshots-panels` from the workflow run and look through every panel. Then upload `en/play-phone/*` in Play Console and `en/appstore-6.9/*` in App Store Connect, in file-name order. Only upload the App Store set from a run whose `Capture on the iOS simulator` job passed; a run where it failed has no `en/appstore-6.9/` folder at all. `en/play-phone-variant-b/*` is variant B of the Play store listing experiment. Store uploads are manual. No workflow holds store-listing write access.
