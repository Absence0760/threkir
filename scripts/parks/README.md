# Park course geometry

Phase 3 of the park courses plan ([#1313](https://github.com/jaredhoward-dev/threkir/issues/1313)): the committed, reviewable pipeline that turns trails in a park into course lines for the `parks` / `park_courses` / `global_segments` tables.

## Layout

```
scripts/parks/
  lib/course_geometry.mjs        pure geometry: trace, measure, simplify, checkpoints
  lib/route_guide.mjs            pure: the course's route guide steps, and their validator
  lib/road_crossings.mjs         pure: where a course crosses a motor road at grade
  lib/course_ends.mjs            pure: the car parks and motor roads around each course end
  lib/golive_gate.mjs            pure: the go-live gate, whose checks decide a park's release
  fetch_snapshot.mjs             network step: OSM ways + USGS elevations + road crossings + course ends -> snapshot.json
  build.mjs                      offline step: spec + snapshot -> <course>.geojson + manifest.json
  lib/catalogue_payload.mjs      pure: manifest + GeoJSON -> the load payload and its SQL
  lib/catalogue_sync.mjs         pure: every park + the publisher -> the release sync's SQL
  lib/catalogue_release.mjs      pure: a manifest's release (live, or staged with a reason)
  lib/third_party_marks.mjs      pure: refuses parkrun / parkwalk in any spec or manifest string
  sync.mjs                       the release sync's park stage (and its manual fallback)
  load.mjs                       fallback: one built park -> one SQL statement on stdout
  local_load.mjs                 local stacks only: every park, staged too, for bin/seed-demo.sh
  lib/catalogue_local.mjs        pure: that load's SQL (seed guard + local official club + the sync)
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
   Use only ways that are open to people on foot. A park's rules usually keep visitors to its designated trails (Virginia state parks: 4VAC5-30-274), so a course over a social trail or a bike-only trail sends runners where they are not allowed. The go-live gate stages a park whose course line uses a way tagged `informal=yes`, `foot=no` or `foot=private`, `access=no` or `access=private` (unless `foot=yes` or `foot=designated` overrides it, as on a foot-only trail), `highway=cycleway` without `foot=yes|designated`, or a mountain-bike trail (`mtb=designated` without foot access, or `bicycle=designated` with `foot=no`). Only ways the line walks are checked, so a pruned spur does not count. It also warns, without refusing, on a walked way tagged `bicycle=designated` with no `foot=yes|designated` or tagged `foot=discouraged`: OSM maps a shared-use path and a bike-only trail the same way (York River State Park's John Blair Trail and Bobcat Run are bike-only on the park's map and carry exactly those tags). Check each warned way against the land manager's map; refuse it in `trail_review` if the map says bike-only, or record the land manager's word in `trail_review.foot_confirmed`, which silences the warning. Prefer named trails and fire roads (`highway=track` with `foot=yes|designated`), and check every unnamed `path` or `footway` against the park's own trail map: OSM often leaves a park's bike-only trails untagged.
3. Check every way the course walks against the land manager's own trail map and record it in the park's `trail_review`: `checked_at`, the `source_urls` checked, `designated` (way ids confirmed as designated trails or open fire roads), `refused` (way id to the reason), and `fords` (designated ways that cross water with no bridge). The build refuses a course whose line walks a refused way, or any way `designated` does not list, naming the way, so a reroute cannot add an unchecked path. A walked way tagged `ford=yes` must be in `fords`, and each course's walked fords go into its `manifest.json` entry as `fords`.
   Where the trail itself is broken at a road (a battlefield's tour road between two trail pieces, with no foot link mapped or built), list the road's way in `road_connectors` (way id to why the course uses it, citing the owner's decision) instead of `designated`. The course may then follow that road, but the gate stages the park if any stretch runs over 250 m in one go (`ROAD_CONNECTOR_MAX_M` in `lib/course_geometry.mjs`) or all of them together make up over 15 % of the course (`ROAD_SHARE_MAX`), and its route guide gets a `road` step with the stretch's length, so the runner is told plainly where they leave the trail and for how far. A way cannot be both a road connector and designated or refused. Cold Harbor is the one park that uses it today.
   Where OSM draws two trail pieces that meet as two dead ends a few metres apart (a near-miss junction, often where a trail crosses a park road on two separate road nodes), list the pair in `joins`: `{ "nodes": [a, b], "reason": "..." }`. The build walks each join as a synthetic step, the gate stages a park with one over 10 m (`JOIN_MAX_M` in `lib/course_geometry.mjs`, inside a phone's GPS error; a wider gap can hide a real obstacle and needs the path mapped), and writes each walked join with its measured `gap_m` into the course's `manifest.json` entry as `joins`. The route guide reads a join as the trail either side of it, never as a step. Fixing the junction in OSM and dropping the entry on the next snapshot is better still. Poor Farm Park is the one park that uses it today.
4. `node scripts/parks/fetch_snapshot.mjs scripts/parks/catalogue/<region>/<park>`
5. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>`. The build refuses a course whose traced distance is more than 5 % off the published figure.
6. Review the `.geojson` on a map (geojson.io, or drop it into QGIS) against the park's trail map before committing.
7. `node scripts/parks/fetch_snapshot.mjs --course-ends-only scripts/parks/catalogue/<region>/<park>` (network: one Overpass query per park), then build again. It records the car parks within 1.5 km and the motor roads within 60 m of every start and finish in the built manifest, as the snapshot's `course_ends`, which the gate reads. Re-run it whenever a course end moves more than 10 m, or the gate stages the park on `source_data`. (`course_end_roads.mjs` still prints the per-end road report as a review aid; the gate now enforces the same runout rule.)

### The go-live gate

No person walks a course before it opens (decisions § 2600). The build holds every course to the machine checks in `lib/golive_gate.mjs` and writes the park's `release` into `manifest.json` from the result: `{ "status": "live" }` when every course passes every check, otherwise `{ "status": "staged", "reason": "Go-live gate failed: <course>: <checks>; ..." }`. Each course's manifest entry lists its `gate_failures` (check and detail), and `gate.park_failures` holds the park-wide ones. `park.json` carries no `release`; the build refuses one that does. Real runs check the course after it opens (the attempts sweep, `docs/features/park_courses.md` § Reports and closures).

| Check | A course fails when |
|---|---|
| `source_data` | the snapshot has no `road_crossings` or `course_ends`, or no `course_ends` entry lies within 10 m of a start or finish (fail closed: missing data stages) |
| `foot_access` | its line walks a way closed to people on foot (`footAccessRefusal`: `foot=no/private`, `access=no/private` without a foot override, `informal=yes`, an unconfirmed bare cycleway, a mountain-bike-only trail) |
| `major_road_crossing` | it crosses a motorway or trunk road (or their ramps) at grade, or a primary road at grade with no traffic signal |
| `road_connector` | one road stretch runs over 250 m |
| `road_share` | road stretches make up over 15 % of the course |
| `join_gap` (park) | any `trail_review.joins` entry spans over 10 m |
| `backtrack` | a lap (a loop or point-to-point course: the whole course) re-runs over 15 % of itself; an out-and-back is exempt |
| `laps` | a 5K takes over 1 lap, a 10K over 2, a half over 3, a marathon or longer over 3 or a lap under 14 km |
| `parking` | no public car park (OSM `amenity=parking`, not private, customers-only or permit) lies within 800 m of the start, or of a point-to-point's finish |
| `end_runout` | the 30 m behind the start or past the finish comes within 3 m of a motor road's centre line (`lib/road_proximity.mjs`) |

A course the build cannot build at all (a way missing from the snapshot, a traced distance over 5 % off the published one, a way `trail_review` has not designated, a parkrun or parkwalk string) is still a build refusal: that is a spec to fix, not a park to stage. A bike-designated way with no foot tag stays a warning (decisions § 2593). See *Loading a park* for what staging does.

Name a course after the park and its distance ("Deep Run Park, 5 km", "Swift Creek Loop, 5 km"). Never after an event that uses the same paths: the build and the payload check refuse any string in the spec or manifest that says parkrun or parkwalk in any spelling, or links to its site (`lib/third_party_marks.mjs`). Where an organised group regularly uses the paths, set the course's `shared_use` (today only `saturday_morning_group`); the clients show a give-way note that names no one.

`node scripts/parks/build.mjs --check <dir>` fails when a committed output no longer matches its spec and snapshot.

Every `park.json` `park` names its `kind`: `park`, or `trail` for a long trail through several parks that belongs to none (the Virginia Capital Trail). `agency` still says who runs it (`other` for the Capital Trail, a VDOT trail). The payload check refuses a missing or unknown kind, and the clients label a trail "Trail" in place of its agency.

A National Park Service unit (`"agency": "nps"` in `park.json`'s `park`) also needs its `nps_park_code`, the NPS Data API `parkCode` (`shen` for Shenandoah, the code in the unit's nps.gov URL). The payload check refuses an `nps` park without one and any other park with one. The daily closures sweep reads the unit's NPS alerts by that code and flags its courses for review (decisions § 2454).

A national forest (George Washington & Jefferson National Forests) is `"agency": "usfs"` and a national wildlife refuge `"agency": "usfws"` (decisions § 2593). Neither takes an `nps_park_code`, and the closures sweep does not read them: no feed of theirs is wired in, so their courses' closure, permit and seasonal-access notes come from the forest or refuge's own pages, recorded in `trail_review` with the URL and checked date. A refuge often limits hours or closes trails for hunts or nesting seasons; say so in the park's `trail_review`.

A trail course (`courses`) is a loop. A point-to-point or out-and-back course on a rail trail is a race course (see *Linear race courses*).

## Route guides

Every course's manifest entry carries a `route_guide` the build generates
(`lib/route_guide.mjs`, decisions § 2448): ordered steps (start, direction,
lap, junction, road, crossing, surface, climb, checkpoint, finish) from the ways the
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

### Road crossings

A `crossing` step of `road` tells a runner where the course crosses a motor
road at grade: `{ "kind": "crossing", "crossing": "road", "name": "Hunter Mill Road", "signal": true, "at_m": 820 }`,
read as "0.8 km: cross Hunter Mill Road at the traffic light." (or "cross the
road. Watch for cars." when OSM gives no name and no signal). It is not the
`road` step kind, which is a stretch the course runs along a road.

The course ways alone cannot show a crossing, because the road through a
shared node is not in them, so the snapshot carries `road_crossings`: for
each course node a motor road passes through, the road's tags and its two
neighbouring nodes, and how far along each a traffic signal sits. A full
`fetch_snapshot.mjs` run fetches it (one Overpass query per park). For a park
whose snapshot is already committed, fetch it alone, which leaves the ways,
nodes and elevations exactly as they are, so no course line moves:

```
node scripts/parks/fetch_snapshot.mjs --road-crossings-only scripts/parks/catalogue/<region>/<park>
node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>
```

A snapshot without `road_crossings` builds as it did before, with no road
crossings. The rule (`lib/road_crossings.mjs`):

- A road counts when its `highway` is a motor road (`MOTOR_ROADS` in
  `lib/road_proximity.mjs`, `_link` included) that cars use (not `access=no` /
  `motor_vehicle=no`). A `service` road counts only when it has a name and is
  not a driveway, parking aisle, drive-through, alley or emergency access: an
  unnamed driveway is nothing a runner can look for, and naming every one would
  bury the roads that matter.
- It must be at grade: a road tagged `bridge` or `tunnel` does not count, and
  neither does a node where the course is on a bridge or in a tunnel on both
  sides.
- The course must cross it: the road's arms lie on both sides of the course's
  path through the node. A road that ends at the trail, or one the course turns
  onto, off or along (a `road_connectors` stretch), is no crossing.
- `signal` is set when OSM puts a traffic signal on the crossing node
  (`crossing=traffic_signals`, `crossing:signals=yes` or
  `highway=traffic_signals`) or on the road within 15 m of it
  (`ROAD_SIGNAL_NEAR_M`, a signal mapped on the junction beside the crosswalk).
  Marked and unmarked crossings read the same.
- Crossings within 40 m along the course (`ROAD_CROSSING_MERGE_M`) are one
  when they share a name or one has none: the two carriageways of a divided
  road, or a road and the unnamed turn lane beside it.

Checking a guide (an owner step, done at the park):

1. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>` and
   read the course's `route_guide.steps` in `manifest.json`, or open the
   course page on a preview deploy.
2. Walk or run the course with the steps in hand. At each junction check the
   turn and the trail name against the signs; check each bridge, ford, road
   crossing (its name and whether it has a traffic light) and surface change,
   and that each climb is where it says.
3. If a step is wrong, the cause is the data: fix the OSM way (name, `surface`,
   `bridge`, `ford`) or crossing node (`crossing=traffic_signals`) upstream and
   re-run `fetch_snapshot.mjs` (`--road-crossings-only` for a road crossing), or change the
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

A park course is the trail as it is, whatever its length. A race course must measure exactly a race distance (`5k`, `10k`, `half`, `marathon`, `50k`, `50mi` = 80,467.2 m, `100k`), so it is built differently, under `race_courses` in `park.json`:

- `lead_in_via` runs from the start area to the loop, and `loop_via` goes once around the loop and back to where the lead-in meets it. Each is a list of OSM node ids walked in order along `osm_ways`. A race reuses parts of long, branching ways, so the via list is what pins the route: a junction and the node after it for every junction, plus a node about every 400 m. Without the extra pins, a hop several kilometres long along fire roads can be cut short by another part of the listed ways (the half-marathon loop traced 515 m short that way).
- `laps` repeats the loop. Marathon and ultra distances are laps of a shorter loop.
- The build cuts the same length off both ends of lead-in + laps + lead-in, so the course measures exactly the race distance. That puts the shared start/finish line on the lead-in. It refuses a course that comes up short, or one where the start line would land past the lead-in onto the loop. Lengthen or shorten the lead-in, or pick another loop.
- The line follows the route, never the other way round. The database trigger that places a course's start and end lines aims each at the point 25 m along the course (`GATE_BEARING_LOOK_AHEAD_M`, mirroring `c_along` in `private.course_end_bearing`; a unit test reads the migration), so a bend within 25 m of an end skews its line. The build derives each bearing from the built points the same way and compares it with the course's direction over its first and last 5 m. Where the two are more than 10 degrees apart, the course's `manifest.json` entry gets a curated `start_gate` / `end_gate` (`lat`, `lng`, `bearing_deg`, `half_width_m`) for that end: on the course's end point, facing the course's direction over those 5 m, with the trigger's 15 m half-width (`GATE_HALF_WIDTH_SEGMENT_M`, mirroring `c_half_width`). The load writes it as a curator line, which the trigger never re-derives. An end within 10 degrees gets no curated line, so the trigger stays its only source. The build still refuses an end with under 10 m of line (`GATE_BEARING_MIN_LINE_M`, `c_min`): the trigger would place no line there at all. The Swift Creek 10K is the one curated course today: its line sits 14 m before the turn off the service road and derives 36.2 degrees off, so both its ends carry a curated line at 68.4 and 248.4 degrees.

Every race course names its `course_shape`: `loop` (above), or `point_to_point` / `out_and_back` (below).

Finding a loop that fits is a search over the park's trail graph. For L the loop length, N the laps, D the race distance and S the lead-in length, a loop fits when (D - 2S) / N <= L < D / N.

The loop need not be one ring. Deep Run Park's `loop_via` goes twice round the ponds, out and back on the woods path, and once more round, with `laps` 1 (it is not N identical laps). Where part of a loop repeats, the length guard cannot catch a skipped repeat (one pond lap is 13 % of the course, under its 25 %), so space the checkpoints closer than the repeated part's length: then each repeat holds a checkpoint earlier in the ring than the one before it, which only another pass reaches. Deep Run Park has 13 (`checkpoints_per_lap` with `laps` 1), and `park_course_real_geometry.test.ts` fails if a run that leaves out any pond lap is timed.

### Linear race courses

A rail trail gives runs no park loop can: a marathon with no laps. A `point_to_point` or `out_and_back` race course replaces `lead_in_via` / `loop_via` / `laps` with:

- `via`: OSM node ids along `osm_ways`, in running order, the same way the loop pins work. On a trail with no branches two nodes are enough.
- `anchor` and `offset_m`: which end of the via path the course is measured from (`via_start` or `via_end`) and how far in from that end it starts or finishes. A `point_to_point` anchored at `via_start` starts `offset_m` along the via path and runs exactly the race distance; anchored at `via_end` it finishes `offset_m` before the via path's last node (the Jamestown marathon finishes at the trail's mile 0). An `out_and_back` is anchored at `via_start`, which is its start and finish, and turns at half the distance.
- `via_ends_at_trail_end` (optional, `true`): the via path ends at the trail's end, and the build refuses it unless the via's last node is a dead end of `osm_ways`. Set it whenever a course is measured from the trail's end; picking that node by eye (the most easterly one) once put a finish 250 m short of the end, across a highway. Pair it with `offset_m` when the trail ends at a road: the Jamestown marathon finishes 50 m before the end so the finish line and the runout stay on the trail, clear of Colonial Parkway.
- `checkpoint_count`: evenly spaced. On an `out_and_back` they sit on the way out only, the last exactly on the turn, so none lands on top of another (the way back passes the same places) and a runner who turns early is never timed.

Where a cut falls between two OSM nodes, the build adds a synthetic node there (a negative id, never an OSM one; `cutSequence` in `lib/course_geometry.mjs`), so the foot-access and trail-review checks, and the route guide, see exactly the course and no more of the via path. A linear course's guide has no direction step. Its manifest entry carries `start` and `finish` (point to point) or `start_finish` and `turn_at_m` (out and back) instead of the loop fields.

OSM often maps a paved multi-use trail as `highway=cycleway` with no foot tag, which the build refuses. Where the land manager says the path is open on foot, record each such way in `trail_review.foot_confirmed` (way id to the land manager's word, with its source in `source_urls`). It lifts only that one refusal; any other reason on the way still refuses. Better still, fix the tag on OSM and drop the entry on the next snapshot.

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
  close a park that is already loaded. A park unstages by passing the gate:
  fix what its `gate_failures` name (reroute, move an end, refetch the
  snapshot), rebuild, commit `park.json` with the outputs, preview with a
  `dry_run` dispatch (its courses move from `staged` to `created`), and
  publish a `backend@*` release.
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
