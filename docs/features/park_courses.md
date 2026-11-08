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
| Server-side matching (issue #1313 Phase 1) | Shipped (migration `20271117002392`, decisions § 2392 / § 2393). See *Matching* |
| Launch backfill (`enqueue_segment_backfill`) | Shipped; an operator call per new course |
| Loop courses | Blocked on #1308 (start = end defeats the end search) |
| Badges (`park_course` family), passport challenge, recap entries, share image | Not built (Phase 5) |
| NPS closures job | Not built (Phase 6) |
| Indexable SSR pages + sitemap | Not built; see *SEO* |

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
- **Fallback.** Run detail still scores the owner's run on view
  (`computeGlobalSegmentEffortsForRun`), now with the same bbox candidates. It
  goes once the job has run in production.
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
4. Queue the launch backfill (`enqueue_segment_backfill`, see *Matching*) so
   existing runs show on the boards the day the course opens.

The pilot loads the first ten courses and keeps the rest staged (owner
decision 4's recommended default). The fixture park in `seed.sql` is fictional
and exists only so local and CI stacks have something to render.

## SEO

`/parks` and everything under it is anon-allowed (`+layout.svelte`), because
both tables grant `select` to anon. None of it is in the sitemap yet, and the
pages are CSR: an empty catalogue in prod would index empty pages, and a course
page names runners once signed in. The indexable version is the `share-entity`
path in [seo.md](seo.md) once courses are loaded.

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
- Server matching: pgTAP `segment_match_jobs_test.sql` (enqueue triggers, the
  bbox lookup, the write and its refusal for replaced bytes, the backfill, grants);
  `supabase/functions/segment-match/*.test.ts`; the Go worker's
  `handler_segment_match_test.go`; `segments/edge_matcher_bundle.test.ts` and
  `segments/track_extent.test.ts` on web.
- Parity pair: `parks/park_courses.test.ts` ↔ `test/park_courses_test.dart`.
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
