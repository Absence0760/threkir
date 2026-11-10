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
| Web `/parks`, `/parks/[region]/[park]`, `/parks/[region]/[park]/[course]` (the full index and the deep-link target; reached from **Run any time** on `/races`, the `/segments` header link and share pages, with a back-link to Races & courses and no run-surface strip of its own; decisions § 2436, superseding the Parks tab of § 2431) | Shipped |
| Web **Run any time** on `/races` (Races & courses, issue #1352): up to eight courses with distance, shape and this season's record, nearest first once the page has a place or the runner's location, otherwise region, park, distance, name; closed courses last (`orderAnyTimeCourses` in `lib/parks/any_time_courses.ts`). Its own loading, error and `EmptyState`, independent of the race calendar above it | Shipped |
| `park_course_records()`: this season's record on every course in one call, a security-invoker wrapper over `global_segment_leaderboard` (migration `20271129002436`) | Shipped |
| Mobile `ParksScreen` → `ParkScreen` → `ParkCourseScreen` (from the **Parks** peer on the Fitness hub's Runs strip, and the segment catalogue's app bar) | Shipped |
| Local fixture park (`seed.sql`, "Fixture State Park") | Shipped, local and CI only |
| Geometry pipeline (`scripts/parks/`) and the load (`private.load_park_catalogue`, migrations `20271126002425` + `20271127002429`, decisions § 2425, § 2429), run by the release's "Sync production state" step (`scripts/parks/sync.mjs`) | Shipped. Pocahontas (Beaver Lake Trail + the five Swift Creek distances) was loaded by hand on 2026-11-10; every backend release since re-syncs it. See *Loading courses* |
| Server-side matching (issue #1313 Phase 1) | Shipped (migration `20271117002392`, decisions § 2392 / § 2393). See *Matching* |
| Launch backfill (`enqueue_segment_backfill`) | Shipped; an operator call per new course |
| Start and end lines; loop courses | Shipped (#1308, migration `20271122002402`, decisions § 2402 / § 2403). See *Matching* |
| Badges (`park_courses` / `park_complete` / `park_passport`), passport challenge metric, recap entries, course share sticker | Shipped (migration `20271123002404`, decisions § 2404 / § 2405); see *Collections* |
| "Report a problem with this course" (issue #1346, migrations `20271213000001`..`005`, decisions § 2449): signed in or signed out, on web and mobile, reviewed and acted on from `/admin/reports`. See *Reports and closures* | Shipped |
| NPS closures job | Not built (Phase 6) |
| Indexable course page `/share/course/<region>/<park>/<course>` + sitemap | Shipped (decisions § 2394); live with the next `terraform apply` + `web@*` deploy. See *SEO* |
| Indexable park pages | Not built; see *SEO* |
| Geometry credit in GPX / KML exports, course GPX (web download, mobile share) | Shipped (decisions § 2395); see *Attribution* |
| Help guide `park-courses`, Learn page `/learn/park-courses-how-timing-works` | Shipped |
| Route guide per course (`park_courses.route_guide`, migration `20271212001344`, decisions § 2448): generated with the geometry, shown on the course page, the share page, its search text and the GPX, web + mobile | Shipped; every Pocahontas guide is still a draft awaiting the owner's ground check. See *Route guide* |

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
- **`laps`** (integer 1-1000, nullable; migration `20271130002438`, decisions
  § 2438): laps of the loop in one timed effort. A race course stores its
  manifest `laps` (the Swift Creek 10K, marathon and 50K are 2), a plain trail
  loop 1, and an out-and-back or point-to-point course null. The clients show a
  "2 laps" chip when it is over 1.
- **`attribution`** (text, 1-300 characters after trimming, nullable): the
  manifest's credit line verbatim ("© OpenStreetMap contributors (ODbL);
  elevation: USGS 3DEP"). It is the only place the load writes the credit: the
  segment's and route's description is the course's own text. The route and
  segment pages (web and mobile) read it through `fetchParkCourseCredit` and
  show it once under the description; the `/share/course` lookup carries it with
  `laps`.
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
- **This season's record on every course at once:** `park_course_records()`,
  for the Run any time list on `/races`. It calls the fastest board per course
  with `p_limit` 1 and that park's `park_season`, so it applies exactly the
  board's rules; a course with nothing this season has no row, and the card
  says no time yet. A failed read leaves the courses listed without records.

## Where courses are surfaced

Owner decision on #1352 (decisions § 2436): park courses live with races,
because a course is something you go and do, not a stretch you happen to run.

- **Races & courses** (`/races`, the run-surface tab): two sections. *Upcoming
  races* is the race calendar, unchanged. *Run any time* lists park courses,
  nearest first once the runner sets a place or uses their location under
  Filters (the same point the race search uses), otherwise in region, park,
  distance and name order, closed courses last. Each card shows distance,
  shape, the park and this season's record, and opens the course page. An
  "All park courses" link goes to `/parks`. Each section loads and fails on
  its own.
- **`/parks`** stays the full index and the deep-link target for share pages
  and posts, with a back-link to Races & courses and no strip.
- **`/segments`** keeps its header link to `/parks`.
- The run-surface strip has no Parks tab (five tabs: Runs · Plans · Races &
  courses · Routes · Segments, in the mobile order).

## The pages (web, issue #1352)

The owner's 2026-11-10 review found the pages primitive; this is what each
one does now. Mobile matches it (`park_courses_screen.dart`).

- **Distances** read through the `park_course_distance` parity pair
  (`lib/parks/park_course_distance.ts` ↔ `park_course_distance.dart`): whole
  when the one-decimal value lands on a whole number, else one decimal, never
  two (`5 km`, `21.1 km`, `3.1 mi`). A park's range reads `5–50 km`.
- **Order:** a park's courses sort closed last, then shortest first, then
  name (`sortParkCourses`), never alphabetically.
- **Shape and laps:** "Loop" is never shown, since nearly every course is one;
  out-and-back and point-to-point are. A course with `laps` over 1 carries an
  "N laps" chip (`courseLapsChip`).
- **`/parks`:** a responsive card grid by region. Each card has a static SVG
  of the park's course lines (no tile request), the agency, and the course
  count with the distance range. The course read is auxiliary: when it fails
  the parks still list.
- **Park page:** region, agency and the park website as separate items; a
  course list (route thumbnail, distance, laps chip, elevation gain,
  difficulty, this season's record and holder when signed in, status pill)
  beside a map of every course line (`ParkCoursesMap`) with each distinct
  start area marked. Pointing at or focusing a course highlights its line.
  The map waits for cookie consent like every MapLibre map. Side by side from
  64rem; map first on a phone.
- **Course page:** the map marks the checkpoints (`CP 1`, `CP 2`, …) and
  carries a key (`ParkMapLegend`): start and finish (one red pin, "Start and
  finish", when the line closes within 30 m, since the finish pin draws over
  the start), checkpoints, the kilometre or mile badges, and the ▶ direction
  arrows. An elevation profile, linked to the map, shows when every point has
  a height. The credit is one line (below). The safety, long-course and
  not-affiliated notices are one callout (`ParkCourseNotices`), safety first.
  "Navigate this course" is the filled primary action, "Download GPX" the
  outline one (primary when there is no route). From 72rem the map, profile
  and boards take the wide column and the stats, actions and notices the
  narrow one, so each column's blocks share its width.
- **Empty board:** the page asks the all-time completions board for one row
  first (it throws on a failed read, so a failure is not read as empty).
  With no time at all, the board kinds, seasons, Compare and the filters are
  hidden and an `EmptyState` explains how to get the first time. They appear
  once there is one; a filtered or this-year board that is empty still says so
  inline.
- **`/share/course/…`** takes the same distance label, laps chip, credit line,
  map key (without checkpoints, which the public lookup does not carry),
  elevation profile and notices callout.

## Route guide

Issue #1344, [decisions § 2448](../architecture/decisions.md). Each course has
a short guide a newcomer can follow: where to park, which way round, and every
turn in order by trail name, with the bridges, fords, surface changes and
climbs on the way, the checkpoints and the laps.

- **Structured, not prose.** `park_courses.route_guide` is
  `{ version: 1, lang, getting_there?, steps }`. A step is one of `start`
  (`name` or `way`), `direction` (`rotation`: `clockwise` /
  `counterclockwise`, with an optional `keep_on` + `landmark`), `lap` (`lap`,
  `of`), `junction` (`turn`: `left` / `right` / `straight`, and `name` or
  `way`: `fire_road` / `road` / `path`), `crossing` (`bridge` / `ford`),
  `surface` (`paved` / `gravel` / `dirt` / `unpaved` / `boardwalk`), `climb`
  (`gain_m`, `length_m`), `checkpoint` (`order`, `of`) and `finish`, each with
  its whole-metre `at_m` along the course. The CHECK
  `private.park_course_route_guide_ok` holds that shape; the generator's
  `routeGuideRefusal` and the payload refuse the same before a release
  connects.
- **Rendered per locale.** Web `parks/route_guide.ts` and mobile
  `route_guide.dart` (a parity pair over `fixtures/route_guide_cases.json`)
  turn each step into one full-sentence template (`parks.guide.*` /
  `parkGuide*`) in all seven locales, so no course needs a translated copy.
  Trail names stay as OSM has them; `getting_there` is free text in the
  guide's `lang` (English today) and is shown with that `lang` attribute. A
  guide any part of which cannot be read is hidden whole, never shown with a
  step missing.
- **Generated, never invented.** `scripts/parks/lib/route_guide.mjs` derives
  the steps from the ordered OSM ways: a junction where the trail name changes
  (a short unnamed bridge or split inside one trail is not one), a junction
  between unnamed ways only where the snapshot shows a branch and the course
  turns, crossings from `bridge` / `ford` tags, surfaces from `surface` tags
  (stretches under 150 m ignored), climbs of at least 12 m at 3.5 %, the
  checkpoints where the build placed them, and the rotation of the loop. A
  lapped race writes lap 1 in full and then only its lap markers, checkpoints
  and what differs (the turn off the loop on the last lap). A landmark ("keep
  Swift Creek Lake on your right") appears only when the snapshot holds a named
  water feature inside the loop; `fetch_snapshot.mjs` does not fetch water
  yet, so today's guides say only which way round.
- **Draft until walked.** `route_guide_checked_at` is null until the owner
  walks the guide at the park and sets `route_guide.ground_checked_at` in
  `park.json`. Until then the course page and the share page show "Drafted
  from map data, not yet checked on the ground." above the steps, the share
  page's meta description says so, and the GPX `<desc>` opens with it. Once
  set, they say "Checked on the ground on <date>." How to check one is in
  [scripts/parks/README.md § Route guides](../../scripts/parks/README.md#route-guides).
- **Where it shows.** The course page (between the actions and the Before you
  run notice), the share page (the same component, `ParkCourseRouteGuide`),
  the share page's JSON-LD description in canonical English (`GUIDE_EN`, held
  to `locales/en.ts` by a test), the course GPX's track `<desc>` in the same
  English, mobile `ParkCourseScreen`, and a line in the `park-courses` help
  guide.

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

## Reports and closures

**Closures.** A course is closed only by a person: the catalogue sync when a
park's manifest stops naming it (note "Removed from the park catalogue."), or a
site admin from `/admin/reports` with a note the course page shows beside the
closed banner. A report never closes or hides a course by itself. A
land-manager request is honoured by closing the course within two business
days (the condition recorded on #1097). The sync never touches an admin's
closure, and an admin cannot reopen a catalogue closure (it would be closed
again on the next release; put the course back in the manifest instead).

**Reporting.** Every course page has "Report a problem with this course" with
its notices, away from Navigate (web: under `ParkCourseNotices`; mobile: at the
foot of `ParkCourseScreen`). It works signed out, so park staff need no
account. The reporter picks a reason (`course_hazard`, `course_closure`,
`course_off_trail`, `land_manager_request` or `other`), writes a note of up to
1000 characters and may leave an email for a reply.

- **One door.** The `park-course-report` Edge Function (`verify_jwt = false`)
  verifies a JWT when one is sent and files as that user, or signed out. It
  validates the body (8 KB cap), drops a filled honeypot with the same answer a
  filed report gets, rate-limits 10 an hour per user or per hashed client
  address (`check_rate_limit`, fail closed), and calls
  `submit_park_course_report`, which only the service role may execute.
- **The database's own caps,** which rotating addresses does not get round:
  25 pending reports per course (a land-manager request is never refused by,
  nor counted toward, this one) and 60 signed-out reports an hour across all
  courses (SQLSTATE `PT429`); one pending report per course per signed-in
  reporter, or per contact email when signed out; at most two links in a note.
- **The row** is a `reports` row (`target_kind = 'park_course'`) carrying
  `contact_email` and `signed_out`, so it shares the moderation queue, the
  legal hold and the retention purge. Anon and authenticated can neither write
  nor read anyone's report.
- **Notices.** Every app admin gets a `park_course_report` notice (in-app,
  email, push; it links to `/admin/reports`) on the first pending report on a
  course and on every land-manager request.
- **Review.** `/admin/reports` sorts land-manager targets after disputes,
  oldest first, with the request's age and its deadline (`landManagerDueAt`:
  two business days, Monday to Friday in UTC, holidays not counted out). The
  detail says "Not signed in" for a signed-out reporter, links the contact
  email for a reply by hand, and opens a course panel that closes the course
  with its note (`admin_set_park_course_status`, which also marks the course's
  pending reports reviewed) or reopens it, logged in
  `park_course_status_actions` and read through `park_course_status_history`.
  Mark reviewed and Dismiss work on course reports as on any other.
- **Personal data.** The contact email goes with a signed-in reporter's
  account (a trigger clears it when `reporter_id` is set null) and 30 days
  after the report is resolved (`private.purge_stale_reports`), unless the
  report is on legal hold. A signed-in reporter's own reports, email included,
  are in their data export (`reports.json`). Threkir sends a reporter no email:
  the acknowledgement is the operator's hand reply.

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
written, and `is_active` is never written. The manifest's attribution goes to
`park_courses.attribution` and each course's laps to `park_courses.laps`; no
description carries the credit (decisions § 2438), and the first sync after
that change reports every earlier course `updated`, with no backfill. The
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

Every course page shows the geometry credit once, under its map (web and mobile):
the course's `attribution` text when it has one, else the label for its
`geometry_source` (`courseCredit` in `lib/parks/park_labels.ts`), never as part
of the description. Every exported file carries it too, because OpenStreetMap's licence asks
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
- [ ] Owner step: walk each course's route guide at the park (Swift Creek
      first), fix what the map data got wrong, and set its
      `route_guide.ground_checked_at` in `park.json`
      ([scripts/parks/README.md § Route guides](../../scripts/parks/README.md#route-guides)).
      Until then every guide ships marked as a draft, which is honest but not
      the end state.
- [ ] Owner check of the park course report defaults (decisions § 2449): the
      30-day contact-email retention, the hand reply in place of an
      acknowledgement email, and the caps (10 an hour per user or address,
      25 pending a course, 60 signed-out an hour), and that
      `TRUSTED_CLIENT_IP_HEADER` is right for the production edge, or every
      signed-out reporter shares one bucket.
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

- Reports and closures: pgTAP
  `apps/backend/supabase/tests/park_course_reports_test.sql` (anon and
  authenticated refused the filing RPC and the table, the insert path signed
  out and in, validation, the per-course and signed-out caps, the admin notices,
  a report never closing a course, the admin close and reopen and their log,
  the contact email cleared on account deletion and 30 days after resolution);
  Deno `apps/backend/supabase/functions/park-course-report/handler.test.ts`
  (validation before any rate-limit spend, the honeypot, the two buckets, the
  reporter passed through, each refusal mapped); web unit
  `apps/web/src/lib/parks/course_report.test.ts` (the deadline, the email
  check, the refusal copy); Playwright
  `apps/web/tests-e2e/parks/park-course-report.spec.ts` (a signed-out
  land-manager request, a signed-in hazard report and its duplicate refusal,
  the admin closing the course from the queue); Flutter
  `apps/mobile_android/test/park_courses_screen_test.dart` group *report a
  problem with this course* (placement, a filed land-manager request, a worded
  refusal).

- Run any time: `apps/web/src/lib/parks/any_time_courses.test.ts` (stable
  order, nearest first with the distance away, unmeasured courses after
  measured ones, closed courses last); pgTAP
  `apps/backend/supabase/tests/park_course_records_test.sql` (this season's
  fastest visible effort, the park's season, no row for a quiet course, a
  pulled park hidden, the caller's own private effort, anon refused);
  Playwright `apps/web/tests-e2e/races/races-and-courses.spec.ts` (the five-tab
  strip, both sections, a course card with its record and its link, no time
  yet, each section's error leaving the other standing, the empty state, failed
  records, nearest first from the granted location, `/parks` from Run any
  time, Segments and directly).
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
- Route guide (#1344): `node --test scripts/parks/lib/route_guide.test.mjs`
  (turns, surfaces, climbs, landmarks, junction rules, laps, offsets,
  determinism, the validator, every committed guide);
  `parks/route_guide.test.ts` ↔ `test/route_guide_test.dart` over
  `fixtures/route_guide_cases.json` (template per step, fail-closed reading,
  `GUIDE_EN` against the English catalogue); pgTAP
  `park_course_route_guide_test.sql` (the shape predicate, the CHECKs, the load
  writing the guide and its date with no backfill, each refusal); Playwright
  `tests-e2e/parks/park-course-route-guide.spec.ts` (the list and the draft
  note on the course and share pages, the checked date, the GPX `<desc>`);
  a widget test in `test/park_courses_screen_test.dart`.
- Pages (#1352): `parks/park_course_distance.test.ts` ↔
  `test/park_course_distance_test.dart` (labels, range, order, shape, laps);
  `parks/course_map.test.ts` (shared starts, a closing loop); Playwright
  `tests-e2e/parks/park-course-pages.spec.ts` (the index card's count and
  range, distance order and labels, one laps chip and no Loop, the meta line,
  the record line, the map key, one credit line from the column and the
  fallback label, the notices callout, one primary action, the empty-board
  invitation with its controls hidden, and the share page).
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
