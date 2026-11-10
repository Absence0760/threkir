# Park courses

Standing time-trial courses in state and national parks, each with a yearly
leaderboard. There is no organiser and no race day: a run that covers the course
is timed against it. Virginia is the pilot. Issue #1313; decisions § 2383.

## What ships today

| Piece | Status |
|---|---|
| `parks` + `park_courses` tables, RLS, grants | Shipped (migration `20271115002383`) |
| Checkpoint rule in the catalogue matcher (`segments` parity pair) | Shipped, web + Dart |
| Season argument on `global_segment_leaderboard` (`p_season`) | Shipped |
| Most-completions board (`global_segment_completions`) | Shipped |
| `park_season` computed field (current year where the park is) | Shipped |
| Web `/parks`, `/parks/[region]/[park]`, `/parks/[region]/[park]/[course]` (the index is the **Parks** tab on the run-surface strip, after Segments; decisions § 2431) | Shipped |
| Mobile `ParksScreen` → `ParkScreen` → `ParkCourseScreen` (from the **Parks** peer on the Fitness hub's Runs strip, and the segment catalogue's app bar) | Shipped |
| Local fixture park (`seed.sql`, "Fixture State Park") | Shipped, local and CI only |
| Geometry pipeline (`scripts/parks/`) and the load (`private.load_park_catalogue`, migrations `20271126002425` + `20271127002429`, decisions § 2425, § 2429), run by the release's "Sync production state" step (`scripts/parks/sync.mjs`) | Shipped. Pocahontas (Beaver Lake Trail + the five Swift Creek distances) was loaded by hand on 2026-11-10; every backend release since re-syncs it. See *Loading courses* |
| Server-side matching (issue #1313 Phase 1) | Shipped (migration `20271117002392`, decisions § 2392 / § 2393). See *Matching* |
| Launch backfill (`enqueue_segment_backfill`) | Shipped; an operator call per new course |
| Start and end lines; loop courses | Shipped (#1308, migration `20271122002402`, decisions § 2402 / § 2403). See *Matching* |
| Badges (`park_courses` / `park_complete` / `park_passport`), passport challenge metric, recap entries, course share sticker | Shipped (migration `20271123002404`, decisions § 2404 / § 2405); see *Collections* |
| NPS closures job | Not built (Phase 6) |
| Indexable course page `/share/course/<region>/<park>/<course>` + sitemap | Shipped (decisions § 2394); live with the next `terraform apply` + `web@*` deploy. See *SEO* |
| Indexable park pages | Not built; see *SEO* |
| Geometry credit in GPX / KML exports, course GPX (web download, mobile share) | Shipped (decisions § 2395); see *Attribution* |
| Help guide `park-courses`, Learn page `/learn/park-courses-how-timing-works` | Shipped |

## Model

- **A course is a catalogue segment that belongs to a park.** `park_courses.global_segment_id`
  is unique, so the segment carries the polyline, the length guard and every
  effort; the course row says where it is and how to run it. The course is its
  own table rather than columns on `global_segments`, so the catalogue stays
  free-standing (decisions § 232) and a park can hold several courses.
- **Columns:** `course_shape` (`loop` / `out_and_back` / `point_to_point`),
  `status` (`open` / `closed` / `seasonal`) with `status_note` and
  `status_checked_at`, `geometry_source` (`osm` / `nps` / `agency` / `traced`)
  with `source_ref` and `source_checked_at`, `difficulty`, `checkpoints`, and a
  nullable `route_id` to the public official route a runner follows. Surface is
  the segment's own `surface`, labelled through the route-surface vocabulary.
- **Parks:** `slug`, `name`, `agency` (`nps` / `state` / `county` / `other`),
  `region_code` (ISO 3166-2, `US-VA`; the URL segment is its lower case),
  `country_code`, `timezone` (IANA, validated against `pg_timezone_names` by a
  trigger), `website_url`, centroid and bounding box, `is_active`.
- Every CHECK vocabulary is a rail in `check_constraint_unions.mjs`, held in the
  `park_courses` parity pair (`apps/web/src/lib/parks/park_courses.ts` ↔
  `apps/mobile_android/lib/park_courses.dart`) and the mobile label switches.

## Checkpoints

`park_courses.checkpoints` is an ordered `[{lat, lng}]` (at most 50). The
matcher only times a run that passes every checkpoint, in order, within the
match tolerance, between the start and end crossings. Each checkpoint takes the
first in-tolerance track index at or after the previous one's. The 25 % length
guard alone admits a cut-through; a checkpoint on the far side of the cut
refuses it.

Both scorers fail closed. They read the checkpoints of every candidate course
before they match: a failed read scores nothing (the server job is retried, the
web fallback stamps nothing so the next view retries), and a course whose list
`parseCourseCheckpoints` cannot read is left out of the sweep.

The run owner can still write their own effort rows (the RLS that has carried
the catalogue since `20270411_001`), which the web fallback below uses, so a
client that skips the checkpoint rule can still insert a time. Removing the
fallback and that policy, once the server job has run in production, closes it.

## Matching

Every run is scored on the server (decisions § 2392):

- **When.** A `segment_match` job is queued when a run's `track_url` is set
  (recorded, imported) and when the bytes behind it are uploaded or rewritten
  (a trigger on `storage.objects` with the path rule the map-match rewrite trigger uses).
- **Where.** The Go job worker claims it and POSTs the payload to the
  `segment-match` Edge Function, which runs the web matcher from the generated
  bundle `_shared/segment_matcher.generated.js` (`pnpm gen:edge-segment-matcher`;
  the web unit suite fails when it is stale). No third implementation of the
  `segments` pair (decisions § 2393).
- **What.** The owner's stored track, with the smoothed sidecar merged when the
  run names it, exactly the line run detail draws for the owner. Candidates come
  from `global_segments_in_bbox` (the track's extent padded 50 m). The result is
  written by `record_segment_match` as the service role, refused for bytes that
  are no longer stored, and read through the unchanged visibility rule.
- **The rule.** A course inherits its catalogue segment's start and end lines
  (derived from the polyline by a trigger, or placed by a curator). A run is
  timed from its forward crossing of the start line to its forward crossing of
  the end line, interpolated between fixes, with the covered distance within
  25 % of the course length and every checkpoint passed in order between the
  two; the fastest pass counts. A loop course is two lines on one point; the
  crossing that ends one lap never starts the next. A run that never crosses
  the lines gets no time, whatever circle it passed through. Only a segment
  without both lines is still matched by the 35 m circles (decisions § 2402).
- **Fallback.** Run detail still scores the owner's run on view
  (`computeGlobalSegmentEffortsForRun`), now with the same bbox candidates. It
  also re-matches an effort an older matcher wrote (its run's
  `global_segments_matcher_version` stamp is behind), by delete then insert,
  and the board says while any visible effort is still a circle match
  (decisions § 2403). It goes once the job has run in production.
- **Launch backfill.** After loading a course, run
  `select enqueue_segment_backfill('<global_segment_id>');` as an admin or the
  service role. It scores existing runs 20 a job in id order, each batch queueing
  the next; a run already scored once is only read again when its stored extent
  (`run_track_extents`) can reach the segment. A second call while one is queued
  returns the same job.

## Seasons and boards

- A season is the calendar year in the **park's** timezone, computed from the
  effort's `started_at`. Nothing is stored per season. A catalogue segment no
  park owns falls back to UTC.
- **Fastest:** `global_segment_leaderboard(..., p_season)`, every existing rule
  kept: one row per athlete, block-guarded, run visibility, club filter,
  shadow-hidden masking, consent-gated age band (§ 727), own-row demographics.
  The five-argument call shape still resolves.
- **Most completions:** `global_segment_completions(p_segment_id, p_season, p_limit)`,
  distinct local days with a visible effort, so laps on one day count once. Same
  visibility, block and shadow-hidden rules; no demographic filters. Ties share
  a rank on the clients.
- Clients ask for "this year" by passing `park_season` back, a computed field on
  `parks`, so no client carries a timezone database.
- Both boards need an account (42501 for anon). Signed-out readers see the
  course, its safety notice and attribution, and a sign-in prompt.

## Wording and safety

The surfaces say *course* and *time trial*, never *race*, *compete* or
*register*. Every course page carries the stay-on-trail notice and the
geometry attribution (`osm` credits OpenStreetMap contributors, `nps` the
National Park Service). A closed course shows a banner and hides "Navigate
this course"; its times and boards stay.

These follow the owner-approved permit conditions (memo
`reviews/legal-park-course-permit.md`, items 5 and 8; decision on #1097):

- **Not affiliated.** Under the attribution, every park and course page
  (web and mobile) and the `/share/course` page say that Threkir publishes the
  courses and the park or its managing agency does not organise, sponsor or
  endorse them, and that park rules, hours, fees and closures apply
  (`parks.notAffiliated`).
- **Long course.** A course over 15 km (`isLongCourse` in the `park_courses`
  pair) adds `parks.longCourseNotice`: start early enough to finish before the
  park closes, shared trail with bikes and horses, water crossings that can be
  impassable after rain. It names no park hours, so no park's hours are
  hardcoded in copy.
- **Official label.** A park course's route is official (the official
  account's club is verified), but its badge reads "Official Threkir course",
  never just "Official", so it cannot read as the park's own. The route page,
  heatmap results and route explorer look the route up in `park_courses`
  (`ParkCourseRouteLookup` on both platforms); an official route shows no
  badge until the lookup answers, and a failed lookup falls back to the
  ordinary badge.
- **Terms.** Terms § 8 Safety says courses, routes and park courses are
  planning information, not organised or supervised events; Threkir does not
  inspect, maintain or mark the trails; the runner follows the land's rules,
  hours, closures and fees and stays on designated trails.

## Loading courses

A course needs a route owned by an official publisher, which no migration can
create, and reviewed geometry, so real courses are not a migration. The
geometry is built and reviewed under `scripts/parks/` (its README has the
pipeline), and **every backend release loads it**: the "Sync production state"
step of `release-backend.yml` runs last, after the migrations and the Edge
Functions, and calls
`private.load_park_catalogue` (migration `20271126002425`, made idempotent by
`20271127002429`; decisions § 2425, § 2429) once per committed
`scripts/parks/catalogue/<region>/<park>/manifest.json`. The club is
committed in `scripts/parks/publisher.json` (slug, with its id as a
cross-check); the author is resolved at run time by
`private.resolve_club_publisher` (migration `20271127100001`) as the club's
active owner, else its earliest-joined active admin, so a change of club
ownership never breaks a release. Only the service role can execute either
function. Nobody runs SQL in production to ship a course: merge the built
park, then publish a `backend@*` release.

The function refuses unless the author is an active owner or admin of the
verified, public club (`private.is_official_publisher`). In one transaction it
upserts the park by slug, with its centroid and bounding box taken from every
course line, and per course, keyed by park and course slug, the catalogue
segment, the `park_courses` row and the public official route. A re-run updates
all three in place, so their ids and every effort survive changed geometry; a
course whose route was deleted gets a new one. Every write is guarded by a
comparison with what is stored, so a course that already matches the manifest
writes nothing and reports `unchanged`, which is what makes the load safe on
every release. A course of the park the manifest no longer names is set
`status = 'closed'` with the note "Removed from the park catalogue.", never
deleted, so its segment and efforts stay; it is reported `closed` on the load
that closes it and not again. If the manifest names it again it reopens
(`updated`). Any other status, an operator's closure included, is never
written, and `is_active` is never written. Every description ends with the manifest's attribution. The
segment's start and end lines follow the manifest: an end the course carries a
curated `start_gate` / `end_gate` for is written as a curator line, on insert
and on every re-load (the build emits one where the derived line would face
more than 10 degrees off the course, decisions § 2424), and every other end is
written source `derived`, so the gates trigger derives it from the new line and
a curated line the manifest has dropped goes back to the derived one. For a
loaded course the manifest is the record: a line placed by hand is replaced by
the next load. It returns one row per course: slug, the
three ids, `created`, `updated`, `unchanged` or `closed`, and the backfill job.
With the backfill flag (the release sync always passes it) a backfill is queued
only for a `created` course or one whose matching geometry changed: the line,
a start or end line, or the checkpoints. A name, description, difficulty or
source change queues none, because every run would score the same.

Race courses (`race_courses` in the manifest, the Swift Creek 5K to 50K) load
as standing park courses with calendar-year boards, not as self-timed races.
Each is a `loop` course, because its start and finish are one line on the
lead-in: the start line faces out along the lead-in and the end line faces
back in (on the 10K both are curated, its line sitting 14 m before a bend), and the matcher never lets the crossing that ends a pass start
the next. Its route carries the race distance as `official_distance_m`.

Shipping a park, or a change to one:

1. Build and review it under `scripts/parks/` and merge it. The official club
   (`threkir`) is committed in `scripts/parks/publisher.json`; the sync picks
   its active owner (else its earliest-joined active admin) as the author when
   it runs. It fails, rolled back, only when the club is not the committed id,
   is not verified, public and visible, or has no active owner or admin. A
   change of owner re-authors the official routes to the new account on the
   next release (`updated`, with no backfill), which keeps them official.
2. Preview it, optionally: run the Release Backend workflow by hand
   (`workflow_dispatch`) with `dry_run` left on. It runs only the sync, behind
   the `production` environment approval, and rolls every stage back after
   printing each course's action to the step summary.
3. Publish a `backend@*` release. After the migrations and functions, "Sync production
   state" loads every committed park, queues the backfills a created or
   redrawn course needs (existing runs show on its boards the day it opens; see
   *Matching*), and writes a created / updated / unchanged / closed table per
   course to the job summary. A dispatch with `dry_run` off does the same
   without a release, from `main` only.
4. Check each new course page and its GPX export for the attribution (the
   pre-deploy checklist below).

Fallback, only if the workflow cannot run: `node scripts/parks/sync.mjs >
sync.sql` prints the same transaction (`--dry-run` ends it in a rollback), to
run with `psql` on the service-role connection. `node scripts/parks/load.mjs
<park dir> --club-id … --author-id … [--enqueue-backfill]` still prints one
park's single call.

The pilot loads the first ten courses and keeps the rest staged (owner
decision 4's recommended default). The fixture park in `seed.sql` is fictional
and exists only so local and CI stacks have something to render.

## SEO

A course's indexable page is `/share/course/<region>/<park>/<course>`, served
by the `share-entity` Lambda (seo.md's dynamic-but-public path, decisions
§ 2394). The key is the in-app URL's own three slugs; the in-app course page
canonicals onto it, and `/sitemap.xml` lists every course
(`courseEntries`). Its head is canonical English (`share_course_meta.ts`):
"<course> at <park> — Threkir", a description with distance, shape, park and
region that says *time trial* and never *race* (a closed course says so), and
a `SportsActivityLocation` JSON-LD placed at the course start and contained
in its `Park`.

The page names the course and its park and never a runner.
`share_course_lookup.ts` reads `park_courses` inner-joined to its park and
catalogue segment and nothing else; the boards stay signed-in only, behind a
link to the in-app course. The course map waits for an explicit consent tap.

`/parks` and the park pages are anon-allowed (`+layout.svelte`) but stay CSR
and out of the sitemap; a `/share/park/<region>/<park>` page is the same
pattern if search data says park pages are where people land.

## Attribution

Every course page shows the geometry credit under its map (web and mobile),
and every exported file carries it too, because OpenStreetMap's licence asks
for the credit on the exported work (decisions § 2395).
`courseAttribution` (the `park_courses` parity pair) maps `geometry_source` to
a credit the `route_gpx` pair writes into GPX `<metadata>`:

| Source | `<copyright author>` | Licence | `<link>` |
|---|---|---|---|
| `osm` | OpenStreetMap contributors | ODbL 1.0 | openstreetmap.org/copyright |
| `nps` | National Park Service | none claimed | nps.gov |
| `agency` | the park | none claimed | the park's `website_url` (https only) |
| `traced` | none (drawn by us) | none | the park's `website_url` |

The `<desc>` carries one English sentence ("Course line © OpenStreetMap
contributors, available under the Open Database License (ODbL)."); KML gets
it as the Document description. Exports of a course's official route (web
route detail GPX / GPX + markers / KML and the roadbook GPX; mobile share as
GPX / GPX + markers / KML) look the course up by `route_id` first and refuse
the export with a message when that read fails on an official route (course
routes are official); any other route exports as before, so an offline export
is never blocked. The course page's own GPX
(web download, mobile share; hidden on a closed course) carries the line, one
`<wpt>` per checkpoint in order, and the credit.

## Help and Learn

The in-app help guide `park-courses` (linked from the course page on web and
mobile) covers checkpoints, seasons in the park's timezone and both boards,
and says that today a time is recorded when the run is opened on the web; the
Phase 1 lane updates that sentence. The public Learn page
`/learn/park-courses-how-timing-works` explains the same timing without
naming the scoring path, and ends on a "Find a park course" CTA to `/parks`.

## Collections

Phase 5 (decisions § 2404 / § 2405). Everything here counts completions, never
rank, and a closed course drops out of the "every" counts while it is closed.

- **Badges** (`achievement_tiers_met`, catalogue `social/badges.ts` ↔
  `badges.dart`): `park_courses` for distinct courses (1 / 5 / 10 / 25),
  `park_complete` for parks where every course not closed is done (1 / 3 / 10;
  only parks with two or more such courses), `park_passport` for regions where
  a course is done in every active park holding one (1 / 3 / 10; only regions
  with three or more such parks). Awarded by statement triggers on
  `global_segment_efforts` insert and on `park_courses` insert / update, so a
  course loaded or closed re-derives for runners already there. The award
  stores a count with `source_id` null, so a public badge names no course or
  park. Private runs count, as for every family.
- **Passport challenge**: the `park_courses` challenge metric counts distinct
  courses (not closed, active park) completed inside the window, optionally
  narrowed by `challenges.park_region_code` (`US-VA`). The yearly official
  passport ("Run 10 Virginia park courses in 2027") is created by the official
  club with that region set; the create forms offer the metric without a
  region. A new effort re-checks the runner's open park challenges, and the
  daily sweep is the backstop.
- **Recap**: the year and month recaps carry `parkCourseCount` and
  `parkCount` (`recapParkSummary` in the `park_courses` pair) and show a
  park courses card when there are any; the owner's page also lists the parks
  run with a course count each. A published recap snapshot holds the two
  counts and no park.
- **Share image**: a run that completed a park course offers the **Park
  course** occasion sticker (photo and sticker styles): the course, its park,
  the time and, when the run is the runner's best this season and inside the
  top 100, its place on that season's fastest board (`run_park_course_times`,
  owner-only; `pickShareCourse` chooses among several).

## Pre-deploy checklist

These gate going live, not the code:

- [x] Owner sign-off (legal-researcher memo) that a passive leaderboard on public
      trails needs no Virginia State Parks special-use permit or NPS special
      event / commercial use authorisation. Recorded on #1097
      (`reviews/legal-park-course-permit.md`), conditional on the notices
      and Terms wording under *Wording and safety*.
- [ ] A self-timed race event in a state or national park has a land-manager
      permit (or written no-objection) recorded in its spec's `permit_ref`
      before the sync creates it. Park courses without a race block need none
      (reviews/legal-park-course-permit.md).
- [ ] Attribution checked on each loaded course's page and GPX export.
- [ ] Written terms from Virginia DCR before any DCR geometry is loaded.
- [ ] NPS API key provisioned before the closures job is built; it must do
      nothing without one.
- [ ] After `20271122002402` reaches production and the `segment-match`
      function carrying the line matcher is deployed, run
      `select enqueue_segment_backfill(id) from global_segments where is_active;`
      once as the service role, so runs nobody reopens are re-matched by their
      lines on the server rather than waiting for an owner view (decisions
      § 2403). Until then their boards show the "measured the old way" note.

## Tests

- Load: pgTAP `apps/backend/supabase/tests/park_catalogue_load_test.sql`
  (creation, an unchanged re-run, changed geometry in place with efforts
  kept, status untouched, a deleted route recreated, the backfill flag, the
  derived lines, curated lines stored as curator lines on insert and update,
  kept across a re-load and a redraw, reset to derived when dropped, the
  official route, every refusal); `node --test
  scripts/parks/lib/catalogue_payload.test.mjs` (the Pocahontas manifest maps
  to six courses, validation, the printed SQL).
- Author resolution: pgTAP `apps/backend/supabase/tests/resolve_club_publisher_test.sql`
  (owner over an earlier admin, earliest admin without an owner, a tie by
  user id, each refusal, no client role can call it).
- Release sync: pgTAP `apps/backend/supabase/tests/park_catalogue_sync_test.sql`
  (a second identical load is `unchanged` and rewrites no row, measured by
  xmin; a backfill on create, a redrawn line, a turned curated line and new
  checkpoints, none on a rename; a dropped course closed once with its effort
  kept, reopened when re-added; an operator's closure untouched; the refusal);
  `node --test scripts/parks/lib/catalogue_sync.test.mjs
  scripts/prod_sync/lib/stages.test.mjs` (the publisher config, the stage SQL,
  the transaction and dry-run rollback, the step summary, and the entry point
  against a stub psql: the password never on psql's command line or in any
  output).
- pgTAP `apps/backend/supabase/tests/park_courses_test.sql`: catalogue RLS,
  admin-only writes, timezone and vocabulary refusals, the season boundary in
  the park's timezone, completions counting days, block and private-run rules.
- Matcher: the `checkpoints:` cases in `segments.test.ts` ↔ `segments_test.dart`, and the shared line cases `fixtures/segments_gate_cases.json` (parallel path, hairpin, wrong direction, two passes, loops, interpolation, off-track fixes, the circle fallback).
- Lines: pgTAP `global_segment_gates_test.sql` (derivation, curator override and reset, `matched_by`, the owner's delete-then-insert re-match); Playwright `tests-e2e/routes/global-segment-gates.spec.ts`.
- Server matching: pgTAP `segment_match_jobs_test.sql` (enqueue triggers, the
  bbox lookup, the write and its refusal for replaced bytes, the backfill, grants);
  `supabase/functions/segment-match/*.test.ts`; the Go worker's
  `handler_segment_match_test.go`; `segments/edge_matcher_bundle.test.ts` and
  `segments/track_extent.test.ts` on web.
- Parity pair: `parks/park_courses.test.ts` ↔ `test/park_courses_test.dart`.
- Attribution: the `courseAttribution` / `parkCourseGpx` cases in the
  `park_courses` pair and the attribution cases in `route_gpx.test.ts` ↔
  `route_gpx_test.dart`; `gpx.test.ts` (web `toGpx` / `toKml`) and
  `route_gpx_share_test.dart` (mobile plain GPX, GPX + markers, KML).
- SEO: `share/share_course_meta.test.ts`, the course cases in
  `share_lookups_public.test.ts`, `sitemap.test.ts` and
  `share_entity_handler.test.ts`, and Playwright
  `tests-e2e/share/course.spec.ts` (share page head and JSON-LD, the
  not-found head, the in-app canonical, the course GPX download).
- Web: `data.test.ts` pins the scorer's fail-closed checkpoint read;
  Playwright `tests-e2e/parks/park-courses.spec.ts` covers the three pages, both
  boards and seasons, the signed-out view, a run that skips a checkpoint, the
  non-affiliation note and the long-course notice either side of 15 km; the
  share spec pins both notices on `/share/course`.
- Mobile: `test/park_courses_screen_test.dart` (incl. both notices).
- Official label: Playwright `tests-e2e/routes/official-content.spec.ts` (a
  park course route reads "Official Threkir course" in the heatmap results and
  on the route page); mobile `test/park_course_routes_test.dart` and the park
  course case in `test/routes_heatmap_screen_test.dart`.
- Collections: pgTAP `park_course_badges_test.sql` (each family, the floors,
  the closed-course rule, the course-update trigger, DNF runs, notifications,
  the challenge metric and its region, `run_park_course_times` and its grants);
  the park cases in `badges.test.ts` ↔ `badges_test.dart`,
  `challenge_goal` / `challenge_progress`, `recap.test.ts` ↔ `recap_test.dart`,
  `share_look` and `run_sticker_canvas.test.ts`, the `recapParkSummary` /
  `pickShareCourse` cases in the `park_courses` pair; Playwright
  `parks/park-course-collections.spec.ts` (badge, recap card, regional
  challenge) and the course case in `runs/share-image-editor.spec.ts`; mobile
  `recap_screen_test.dart`, `run_share_card_test.dart`,
  `challenge_detail_screen_test.dart` and `api_client`
  `park_course_reads_test.dart`.

## Owner decisions taken as the issue's recommended default

1. Season boundary: calendar year.
2. Boards first: fastest this year plus completions.
3. Gender split: the existing filter is kept on the fastest board.
4. Pilot breadth: load ten, keep the rest staged.
5. Brand name: "Park courses".
