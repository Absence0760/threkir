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
| Web `/parks`, `/parks/[region]/[park]`, `/parks/[region]/[park]/[course]` | Shipped |
| Mobile `ParksScreen` → `ParkScreen` → `ParkCourseScreen` (from the segment catalogue's app bar) | Shipped |
| Local fixture park (`seed.sql`, "Fixture State Park") | Shipped, local and CI only |
| **Virginia geometry** | **Not loaded.** See *Loading courses* |
| Server-side matching (issue #1313 Phase 1) | Not built. Efforts are still written by the web run-detail page only |
| Loop courses | Blocked on #1308 (start = end defeats the end search) |
| Badges (`park_course` family), passport challenge, recap entries, share image | Not built (Phase 5) |
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

The scorer fails closed. `computeGlobalSegmentEffortsForRun` reads every
course's checkpoints before it matches: a failed read scores nothing and stamps
nothing (the next view retries), and a course whose list `parseCourseCheckpoints`
cannot read is left out of the sweep.

The run owner still writes their own effort rows (the RLS that has carried the
catalogue since `20270411_001`), so a client that skips the checkpoint rule can
still insert a time. Moving the write to the server (Phase 1) closes that.

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

The surfaces say *course* and *time trial*, never *race*. Every course page
carries the stay-on-trail notice and the geometry attribution (`osm` credits
OpenStreetMap contributors, `nps` the National Park Service). A closed course
shows a banner and hides "Navigate this course"; its times and boards stay.

## Loading courses

A course needs a route owned by the official account, which no migration can
create, and reviewed geometry. Real courses are therefore an operator load and
none are in the tree yet: the Virginia trail names and distances in #1313 are
unverified, and no openly licensed geometry was sourced in this change.

1. Extract the trail line (NPS Public Trails first, then OpenStreetMap via
   Overpass; Virginia DCR data only after DCR confirms terms in writing; never
   AllTrails, Strava or Garmin routes). Stitch, orient, simplify, fill
   elevation, check the length against the park's own published figure (within
   5 %), and place checkpoints on the far side of every cut a runner could take.
2. As the service role: insert the `global_segments` row (description carries
   the attribution), the `parks` row if new, then the `park_courses` row with
   `geometry_source`, `source_ref` and `source_checked_at`.
3. Draw or import the public route under the official account and set
   `park_courses.route_id`.

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

## Pre-deploy checklist

These gate going live, not the code:

- [ ] Owner sign-off (legal-researcher memo) that a passive leaderboard on public
      trails needs no Virginia State Parks special-use permit or NPS special
      event / commercial use authorisation. Record it on #1097.
- [ ] Attribution checked on each loaded course's page and GPX export.
- [ ] Written terms from Virginia DCR before any DCR geometry is loaded.
- [ ] NPS API key provisioned before the closures job is built; it must do
      nothing without one.

## Tests

- pgTAP `apps/backend/supabase/tests/park_courses_test.sql`: catalogue RLS,
  admin-only writes, timezone and vocabulary refusals, the season boundary in
  the park's timezone, completions counting days, block and private-run rules.
- Matcher: the `checkpoints:` cases in `segments.test.ts` ↔ `segments_test.dart`.
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
  boards and seasons, the signed-out view, and a run that skips a checkpoint.
- Mobile: `test/park_courses_screen_test.dart`.

## Owner decisions taken as the issue's recommended default

1. Season boundary: calendar year.
2. Boards first: fastest this year plus completions.
3. Gender split: the existing filter is kept on the fastest board.
4. Pilot breadth: load ten, keep the rest staged.
5. Brand name: "Park courses".
