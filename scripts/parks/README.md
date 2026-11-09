# Park course geometry

Phase 3 of the park courses plan ([#1313](https://github.com/Absence0760/threkir/issues/1313)): the committed, reviewable pipeline that turns trails in a park into course lines for the `parks` / `park_courses` / `global_segments` tables.

## Layout

```
scripts/parks/
  lib/course_geometry.mjs        pure geometry: trace, measure, simplify, checkpoints
  fetch_snapshot.mjs             network step: OSM ways + USGS elevations -> snapshot.json
  build.mjs                      offline step: spec + snapshot -> <course>.geojson + manifest.json
  lib/catalogue_payload.mjs      pure: manifest + GeoJSON -> the load payload and its SQL
  load.mjs                       operator step: built park -> one SQL statement on stdout
  catalogue/<region>/<park>/
    park.json                    the spec, written by hand
    snapshot.json                source data, written by fetch_snapshot.mjs
    <course>.geojson             one per course, written by build.mjs
    manifest.json                what the operator load reads, written by build.mjs
```

## Adding a course

1. Find the trail's OSM way ids (the OSM website's "Query features" tool, or an Overpass query on the park boundary) and the node where the course starts. Use OSM or NPS data only. Never trace from AllTrails, Strava, Garmin or another app's routes (their terms forbid it), and use Virginia DCR data only once DCR has confirmed the terms in writing.
2. Add the course to the park's `park.json`: `osm_ways` lists the ways of ONE loop (dead-end spurs such as piers are pruned automatically), `start_node` is where timing starts, and `published` is the park's own distance with its source URL.
   Use only ways that are open to people on foot. A park's rules usually keep visitors to its designated trails (Virginia state parks: 4VAC5-30-274), so a course over a social trail or a bike-only trail sends runners where they are not allowed. The build refuses a course whose line uses a way tagged `informal=yes`, `foot=no` or `foot=private`, `access=no` or `access=private` (unless `foot=yes` or `foot=designated` overrides it, as on a foot-only trail), `highway=cycleway` without `foot=yes|designated`, or a mountain-bike trail (`mtb=designated` without foot access, or `bicycle=designated` with `foot=no`). Only ways the line walks are checked, so a pruned spur does not count. Prefer named trails and fire roads (`highway=track` with `foot=yes|designated`), and check every unnamed `path` or `footway` against the park's own trail map: OSM often leaves a park's bike-only trails untagged.
3. Check every way the course walks against the land manager's own trail map and record it in the park's `trail_review`: `checked_at`, the `source_urls` checked, `designated` (way ids confirmed as designated trails or open fire roads), `refused` (way id to the reason), and `fords` (designated ways that cross water with no bridge). The build refuses a course whose line walks a refused way, or any way `designated` does not list, naming the way, so a reroute cannot add an unchecked path. A walked way tagged `ford=yes` must be in `fords`, and each course's walked fords go into its `manifest.json` entry as `fords`.
4. `node scripts/parks/fetch_snapshot.mjs scripts/parks/catalogue/<region>/<park>`
5. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>`. The build refuses a course whose traced distance is more than 5 % off the published figure.
6. Review the `.geojson` on a map (geojson.io, or drop it into QGIS) against the park's trail map before committing.

`node scripts/parks/build.mjs --check <dir>` fails when a committed output no longer matches its spec and snapshot.

Only loop courses are built so far. Out-and-back and point-to-point courses (the rail trails) are added when the first one is specced.

## Race courses

A park course is the trail as it is, whatever its length. A race course must measure exactly a race distance (`5k`, `10k`, `half`, `marathon`, `50k`), so it is built differently, under `race_courses` in `park.json`:

- `lead_in_via` runs from the start area to the loop, and `loop_via` goes once around the loop and back to where the lead-in meets it. Each is a list of OSM node ids walked in order along `osm_ways`. A race reuses parts of long, branching ways, so the via list is what pins the route: a junction and the node after it for every junction, plus a node about every 400 m. Without the extra pins, a hop several kilometres long along fire roads can be cut short by another part of the listed ways (the half-marathon loop traced 515 m short that way).
- `laps` repeats the loop. Marathon and ultra distances are laps of a shorter loop.
- The build cuts the same length off both ends of lead-in + laps + lead-in, so the course measures exactly the race distance. That puts the shared start/finish line on the lead-in. It refuses a course that comes up short, or one where the start line would land past the lead-in onto the loop. Lengthen or shorten the lead-in, or pick another loop.
- The line follows the route, never the other way round. The database trigger that places a course's start and end lines aims each at the point 25 m along the course (`GATE_BEARING_LOOK_AHEAD_M`, mirroring `c_along` in `private.course_end_bearing`; a unit test reads the migration), so a bend within 25 m of an end skews its line. The build derives each bearing from the built points the same way and compares it with the course's direction over its first and last 5 m. Where the two are more than 10 degrees apart, the course's `manifest.json` entry gets a curated `start_gate` / `end_gate` (`lat`, `lng`, `bearing_deg`, `half_width_m`) for that end: on the course's end point, facing the course's direction over those 5 m, with the trigger's 15 m half-width (`GATE_HALF_WIDTH_SEGMENT_M`, mirroring `c_half_width`). The load writes it as a curator line, which the trigger never re-derives. An end within 10 degrees gets no curated line, so the trigger stays its only source. The build still refuses an end with under 10 m of line (`GATE_BEARING_MIN_LINE_M`, `c_min`): the trigger would place no line there at all. The Swift Creek 10K is the one curated course today: its line sits 14 m before the turn off the service road and derives 36.2 degrees off, so both its ends carry a curated line at 68.4 and 248.4 degrees.

Finding a loop that fits is a search over the park's trail graph. For L the loop length, N the laps, D the race distance and S the lead-in length, a loop fits when (D - 2S) / N <= L < D / N.

## Loading a park

`load.mjs` turns a built park into ONE statement calling
`private.load_park_catalogue` (migration `20271126002425`, decisions § 2425). It
connects to nothing; the operator runs its output in production as the service
role.

```
node scripts/parks/load.mjs scripts/parks/catalogue/us-va/pocahontas \
  --club-id <official club uuid> --author-id <owner/admin uuid> [--enqueue-backfill] > pocahontas.sql
```

- `--club-id` is the verified, public club that publishes the courses, and
  `--author-id` an active owner or admin of it. The function refuses any other
  pair, so the routes it writes are official.
- Every `courses` entry and every `race_courses` entry becomes a park course. A
  race course is a `loop` (its start and finish are one line on the lead-in),
  and its route's `official_distance_m` is the race distance.
- It refuses what the database would: a bad slug or vocabulary value, more than
  50 checkpoints, a coordinate out of range, a GeoJSON whose line no longer
  matches the manifest (point count, or length more than 1 % off), a loop whose
  ends are more than 25 m apart, a race course that does not measure its race
  distance.
- `--enqueue-backfill` also queues the launch backfill for each course. Leave it
  off to queue the backfill as its own step.

A re-run updates the park and each course's segment, course row and route in
place, so the same statement is how a rebuilt course reaches production. The
steps around it are in [park_courses.md § Loading courses](../../docs/features/park_courses.md#loading-courses).

## Licence

Everything under `catalogue/` that comes from OpenStreetMap (`snapshot.json`, the `.geojson` files and the geometry in `manifest.json`) is © OpenStreetMap contributors and available under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Elevations are from the USGS 3D Elevation Program (public domain). Course pages and GPX exports must credit "© OpenStreetMap contributors".
