# Park course geometry

Phase 3 of the park courses plan ([#1313](https://github.com/Absence0760/threkir/issues/1313)): the committed, reviewable pipeline that turns trails in a park into course lines for the `parks` / `park_courses` / `global_segments` tables.

## Layout

```
scripts/parks/
  lib/course_geometry.mjs        pure geometry: trace, measure, simplify, checkpoints
  lib/route_guide.mjs            pure: the course's route guide steps, and their validator
  fetch_snapshot.mjs             network step: OSM ways + USGS elevations -> snapshot.json
  build.mjs                      offline step: spec + snapshot -> <course>.geojson + manifest.json
  lib/catalogue_payload.mjs      pure: manifest + GeoJSON -> the load payload and its SQL
  lib/catalogue_sync.mjs         pure: every park + the publisher -> the release sync's SQL
  lib/catalogue_release.mjs      pure: a park's release (live, or staged with a reason)
  lib/third_party_marks.mjs      pure: refuses parkrun / parkwalk in any spec or manifest string
  sync.mjs                       the release sync's park stage (and its manual fallback)
  load.mjs                       fallback: one built park -> one SQL statement on stdout
  publisher.json                 the official club the courses publish as (slug + id)
  catalogue/<region>/<park>/
    park.json                    the spec, written by hand
    snapshot.json                source data, written by fetch_snapshot.mjs
    <course>.geojson             one per course, written by build.mjs
    manifest.json                what the load reads, written by build.mjs
```

## Adding a course

1. Find the trail's OSM way ids (the OSM website's "Query features" tool, or an Overpass query on the park boundary) and the node where the course starts. Use OSM or NPS data only. Never trace from AllTrails, Strava, Garmin or another app's routes (their terms forbid it), and use Virginia DCR data only once DCR has confirmed the terms in writing.
2. Add the course to the park's `park.json`: `osm_ways` lists the ways of ONE loop (dead-end spurs such as piers are pruned automatically), `start_node` is where timing starts, and `published` is the park's own distance with its source URL.
   Use only ways that are open to people on foot. A park's rules usually keep visitors to its designated trails (Virginia state parks: 4VAC5-30-274), so a course over a social trail or a bike-only trail sends runners where they are not allowed. The build refuses a course whose line uses a way tagged `informal=yes`, `foot=no` or `foot=private`, `access=no` or `access=private` (unless `foot=yes` or `foot=designated` overrides it, as on a foot-only trail), `highway=cycleway` without `foot=yes|designated`, or a mountain-bike trail (`mtb=designated` without foot access, or `bicycle=designated` with `foot=no`). Only ways the line walks are checked, so a pruned spur does not count. Prefer named trails and fire roads (`highway=track` with `foot=yes|designated`), and check every unnamed `path` or `footway` against the park's own trail map: OSM often leaves a park's bike-only trails untagged.
3. Check every way the course walks against the land manager's own trail map and record it in the park's `trail_review`: `checked_at`, the `source_urls` checked, `designated` (way ids confirmed as designated trails or open fire roads), `refused` (way id to the reason), and `fords` (designated ways that cross water with no bridge). The build refuses a course whose line walks a refused way, or any way `designated` does not list, naming the way, so a reroute cannot add an unchecked path. A walked way tagged `ford=yes` must be in `fords`, and each course's walked fords go into its `manifest.json` entry as `fords`.
4. `node scripts/parks/fetch_snapshot.mjs scripts/parks/catalogue/<region>/<park>`
5. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>`. The build refuses a course whose traced distance is more than 5 % off the published figure.
6. Review the `.geojson` on a map (geojson.io, or drop it into QGIS) against the park's trail map before committing.

Every `park.json` declares its `release` (decisions § 2460): `{ "status": "staged", "reason": "..." }` for a park that must not load yet, or `{ "status": "live" }`. A new park starts staged until its owner checks are done; there is no default, and a missing or unknown release fails the build. See *Loading a park* for what staging does and how to unstage.

Name a course after the park and its distance ("Deep Run Park, 5 km", "Swift Creek Loop, 5 km"). Never after an event that uses the same paths: the build and the payload check refuse any string in the spec or manifest that says parkrun or parkwalk in any spelling, or links to its site (`lib/third_party_marks.mjs`). Where an organised group regularly uses the paths, set the course's `shared_use` (today only `saturday_morning_group`); the clients show a give-way note that names no one.

`node scripts/parks/build.mjs --check <dir>` fails when a committed output no longer matches its spec and snapshot.

A National Park Service unit (`"agency": "nps"` in `park.json`'s `park`) also needs its `nps_park_code`, the NPS Data API `parkCode` (`shen` for Shenandoah, the code in the unit's nps.gov URL). The payload check refuses an `nps` park without one and any other park with one. The daily closures sweep reads the unit's NPS alerts by that code and flags its courses for review (decisions § 2454).

Only loop courses are built so far. Out-and-back and point-to-point courses (the rail trails) are added when the first one is specced.

## Route guides

Every course's manifest entry carries a `route_guide` the build generates
(`lib/route_guide.mjs`, decisions § 2448): ordered steps (start, direction,
lap, junction, crossing, surface, climb, checkpoint, finish) from the ways the
course walks, their OSM names and tags, the snapshot's elevations and the
checkpoints. Clients render the steps in each locale, so nothing in it is
prose except the course's `getting_there` note. `--check` covers it like the
rest of the manifest.

Per course in `park.json`:

```json
"route_guide": {
  "getting_there": "Park at the boat-ramp lot. The start line is on ...",
  "ground_checked_at": null
}
```

- `getting_there` is free text in English (the guide's `lang`), at most 500
  characters: where to park and how to reach the start line. Write only what
  the park's own map or the spec's `start_note` supports.
- `ground_checked_at` stays `null` until a person has walked the guide at the
  park. While it is null, every surface says the guide is drafted from map
  data and not yet checked on the ground.

Checking a guide (an owner step, done at the park):

1. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>` and
   read the course's `route_guide.steps` in `manifest.json`, or open the
   course page on a preview deploy.
2. Walk or run the course with the steps in hand. At each junction check the
   turn and the trail name against the signs; check each bridge, ford and
   surface change, and that each climb is where it says.
3. If a step is wrong, the cause is the data: fix the OSM way (name, `surface`,
   `bridge`, `ford`) upstream and re-run `fetch_snapshot.mjs`, or change the
   course's ways in `park.json`. Never edit `manifest.json` by hand; `--check`
   would fail it.
4. When every step matches, set `ground_checked_at` to the date you walked it
   (`YYYY-MM-DD`), rebuild, and commit `park.json` with `manifest.json`. The
   next backend release writes it as `park_courses.route_guide_checked_at`.
5. A later rebuild that changes the course's steps means the check no longer
   covers them: walk the changed steps again before keeping the date.

What the generator will not do: name a landmark the snapshot does not hold
(`loopLandmark` needs a named water feature inside the loop, and
`fetch_snapshot.mjs` does not fetch water yet), or call a split between two
unnamed ways a junction unless the snapshot shows a branch there. Thresholds
(`SHORT_RUN_M`, `SURFACE_MIN_RUN_M`, `CLIMB_MIN_GAIN_M`, `CLIMB_MIN_GRADE`) are
at the top of `lib/route_guide.mjs`.

## Race courses

A park course is the trail as it is, whatever its length. A race course must measure exactly a race distance (`5k`, `10k`, `half`, `marathon`, `50k`), so it is built differently, under `race_courses` in `park.json`:

- `lead_in_via` runs from the start area to the loop, and `loop_via` goes once around the loop and back to where the lead-in meets it. Each is a list of OSM node ids walked in order along `osm_ways`. A race reuses parts of long, branching ways, so the via list is what pins the route: a junction and the node after it for every junction, plus a node about every 400 m. Without the extra pins, a hop several kilometres long along fire roads can be cut short by another part of the listed ways (the half-marathon loop traced 515 m short that way).
- `laps` repeats the loop. Marathon and ultra distances are laps of a shorter loop.
- The build cuts the same length off both ends of lead-in + laps + lead-in, so the course measures exactly the race distance. That puts the shared start/finish line on the lead-in. It refuses a course that comes up short, or one where the start line would land past the lead-in onto the loop. Lengthen or shorten the lead-in, or pick another loop.
- The line follows the route, never the other way round. The database trigger that places a course's start and end lines aims each at the point 25 m along the course (`GATE_BEARING_LOOK_AHEAD_M`, mirroring `c_along` in `private.course_end_bearing`; a unit test reads the migration), so a bend within 25 m of an end skews its line. The build derives each bearing from the built points the same way and compares it with the course's direction over its first and last 5 m. Where the two are more than 10 degrees apart, the course's `manifest.json` entry gets a curated `start_gate` / `end_gate` (`lat`, `lng`, `bearing_deg`, `half_width_m`) for that end: on the course's end point, facing the course's direction over those 5 m, with the trigger's 15 m half-width (`GATE_HALF_WIDTH_SEGMENT_M`, mirroring `c_half_width`). The load writes it as a curator line, which the trigger never re-derives. An end within 10 degrees gets no curated line, so the trigger stays its only source. The build still refuses an end with under 10 m of line (`GATE_BEARING_MIN_LINE_M`, `c_min`): the trigger would place no line there at all. The Swift Creek 10K is the one curated course today: its line sits 14 m before the turn off the service road and derives 36.2 degrees off, so both its ends carry a curated line at 68.4 and 248.4 degrees.

Finding a loop that fits is a search over the park's trail graph. For L the loop length, N the laps, D the race distance and S the lead-in length, a loop fits when (D - 2S) / N <= L < D / N.

The loop need not be one ring. Deep Run Park's `loop_via` goes twice round the ponds, out and back on the woods path, and once more round, with `laps` 1 (it is not N identical laps). Where part of a loop repeats, the length guard cannot catch a skipped repeat (one pond lap is 13 % of the course, under its 25 %), so space the checkpoints closer than the repeated part's length: then each repeat holds a checkpoint earlier in the ring than the one before it, which only another pass reaches. Deep Run Park has 13 (`checkpoints_per_lap` with `laps` 1), and `park_course_real_geometry.test.ts` fails if a run that leaves out any pond lap is timed.

## Loading a park

Every backend release loads the catalogue; nobody runs SQL in production. The
"Sync production state" step of `.github/workflows/release-backend.yml` runs
last, after the migrations and the Edge Functions (`apps/backend/scripts/sync-production-state.sh`, stages in
`scripts/prod_sync/run.mjs`, decisions § 2429). Its park stage, `sync.mjs`,
finds every `catalogue/<region>/<park>/manifest.json`, validates it as below,
and calls `private.load_park_catalogue` (migrations `20271126002425` +
`20271127002429` + `20271130002438`, decisions § 2425) once per park as the official club in
`publisher.json`, with the backfill flag on, in one transaction. The job's step
summary lists every course as `created`, `updated`, `unchanged` or `closed`.

- **Idempotent.** A course that already matches its manifest writes nothing and
  reports `unchanged`, so an unchanged catalogue is safe on every release.
- **Backfill only where it changes a result.** A backfill is queued for a
  `created` course, or when the line, a start or end line, or the checkpoints
  changed. A name, description, difficulty or source change queues none.
- **Staged parks are held out.** A park whose manifest `release` is `staged`
  is validated like the rest and never loaded: each of its courses is a
  `staged` row in the step summary and the dry run, and the summary's note
  names the park and its reason. `load.mjs` refuses one too. Staging does not
  close a park that is already loaded. To unstage: set `park.json`'s
  `release` to `{ "status": "live" }`, rebuild, commit `park.json` and
  `manifest.json`, preview with a `dry_run` dispatch (its courses move from
  `staged` to `created`), and publish a `backend@*` release.
- **Never deletes.** A course its park's manifest no longer names is set
  `closed` ("Removed from the park catalogue."), keeping its segment and every
  effort, and reopens if the manifest names it again. A closure an operator
  set is never touched.
- `publisher.json` holds the official club only: `club_slug`, and `club_id` as
  a cross-check (a public id, not a secret). No author is committed. The stage
  first calls `private.resolve_club_publisher` (migration `20271127100001`),
  which returns the club's active owner, else its active admin with the
  earliest `joined_at` (then the lowest user id), so an ownership change never
  breaks a release. It fails the stage, rolled back, when the slug's club is
  not the committed id, is not verified, public and visible, or has no active
  owner or admin. The account it picks is one `load_park_catalogue` accepts,
  so the routes it writes are official; after an ownership change they are
  re-authored to the new account (`updated`, no backfill). The summary's
  `published_by` column names it.
- Every `courses` entry and every `race_courses` entry becomes a park course. A
  race course is a `loop` (its start and finish are one line on the lead-in),
  and its route's `official_distance_m` is the race distance.
- `park_courses.laps` is a race course's `laps`. A trail course takes its
  entry's `laps` if it has one, else 1 for a `loop` and null for an
  `out_and_back` or `point_to_point` course (decisions § 2438).
- Each course's `shared_use` is written to `park_courses.shared_use`
  (migration `20271215120001`); a change reports it `updated` with no backfill.
- Each course's `route_guide` and `route_guide_checked_at` are written to the
  `park_courses` columns of those names (migration `20271212001344`). A change
  to either reports the course `updated` with no backfill.
- The manifest's `attribution` is written to `park_courses.attribution` on
  every course, and only there: the segment's and route's description is the
  course's own text. The first sync after migration `20271130002438` reports
  every course loaded before it `updated` (the credit leaves the description,
  laps and attribution are written), with no backfill.
- It refuses what the database would, before connecting: a bad slug or
  vocabulary value, more than 50 checkpoints, a coordinate out of range, a
  GeoJSON whose line no longer matches the manifest (point count, or length
  more than 1 % off), a loop whose ends are more than 25 m apart, a race course
  that does not measure its race distance, laps that are not a whole number
  from 1 to 1000, an attribution over 300 characters, a `shared_use` outside
  its vocabulary, and any string naming parkrun or parkwalk.

To preview a change against production, run the Release Backend workflow by
hand with `dry_run` on (the default): it runs only the sync, behind the
`production` environment approval, and rolls it back after writing the table.
With `dry_run` off, from `main`, it syncs without a release.

### Fallback: the SQL by hand

Only when the workflow cannot run. Both commands print SQL and connect to
nothing; run the output with `psql` on the service-role connection.

```
node scripts/parks/sync.mjs [--dry-run] > sync.sql
node scripts/parks/load.mjs scripts/parks/catalogue/us-va/pocahontas \
  --club-id <official club uuid> --author-id <owner/admin uuid> [--enqueue-backfill] > pocahontas.sql
```

`sync.mjs` prints the whole release transaction (`--dry-run` ends it in a
rollback). `load.mjs` prints one park's call; with `--enqueue-backfill` it has
the same backfill rule as the sync.

The steps around a load are in [park_courses.md § Loading courses](../../docs/features/park_courses.md#loading-courses).

## Licence

Everything under `catalogue/` that comes from OpenStreetMap (`snapshot.json`, the `.geojson` files and the geometry in `manifest.json`) is © OpenStreetMap contributors and available under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Elevations are from the USGS 3D Elevation Program (public domain). Course pages and GPX exports must credit "© OpenStreetMap contributors".
