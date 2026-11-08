# Provenance labels and organiser course alerts

Issue #1190, slices "Provenance labels ... and organiser course alerts" and
"Badge rendering on routes, plans, routines, challenges, race listings".
Decisions [§ 2406](../architecture/decisions.md) (labels) and
[§ 2407](../architecture/decisions.md) (course alerts). Verification
itself (how a club becomes `is_verified`) is out of scope here; this doc
builds on `clubs.is_verified` as the source of truth.

## The four labels

| Kind | Visible word | Means | Derived from |
|---|---|---|---|
| `official` | Official | Published by an owner/admin of a verified, public, unhidden club | content: `is_official` (§ 2228); listing: `organiser_is_official`; course: `organiser_is_official` and `course_source = 'official'` |
| `verified_source` | Verified source | Listed by a race data partner or provider sync | listing only: `provider <> 'manual'` and `is_verified` |
| `traced` | Traced | Drawn by a verified club from the race's published map | course only: `organiser_is_official` and `course_source = 'traced'` |
| `community` | Community | Nobody official vouches for it | everything else |

Every input is server-derived and client-proof: `clubs.is_verified` is
service-role only, roles change only through a club admin, and the claim
columns on `race_listings` are frozen by `force_unverified_listing`.
`public_race_listings.organiser_is_official` (migration `20271124002406`)
is computed at read time, so revoking a club, making it private or having
the report flow hide it removes the badge from its listings, their courses
and their course alerts at once. `search_race_listings` returns the same
column (`20271124002410`).

The classification is the `provenance` parity pair: web
`apps/web/src/lib/social/provenance.ts`, mobile
`apps/mobile_android/lib/provenance.dart`, shared fixture
`fixtures/provenance_cases.json`. The label text and icon per kind are
render glue in `ProvenanceBadge` (web `components/ProvenanceBadge.svelte`,
mobile `widgets/provenance_badge.dart`); `OfficialBadge` is its official
kind.

**Accessibility.** A badge is never colour alone: each kind has its own
icon (ribbon / database / map / people) and a visible word, and a screen
reader hears one sentence (`Official: published by a verified organiser`,
`Verified source: listed by a race data partner`, ...) rather than an icon
name.

**Where it renders.** Cards show every kind except `community`; detail
pages show the listing's and the course's kind always.

| Surface | Web | Mobile |
|---|---|---|
| Race calendar card | `RaceCalendarCard.svelte` | `races_screen.dart` `_RaceCard` |
| Race page: listing + course | `/races/[id]` | `RaceDetailScreen` |
| Routes, plans, challenges, session plans | existing `OfficialBadge` placements (§ 2228) | same |
| Club gym routine templates | club page Templates | `ClubDetailScreen` Templates |
| Gym routine detail | `/gym/routines/[id]` | not yet (the detail reads the local store) |

## Organiser course alerts

`course_alerts` (migration `20271124002407`): one short notice (`reroute`,
`closure`, `direction`, `notice`; 1-500 characters) on exactly one race
listing or route. Only `post_course_alert` / `delete_course_alert` write
it, and both require `private.is_official_publisher` for the listing's
organiser club or the route's owning club. Anyone who can see the course
reads its alerts while the club stays verified; who typed an alert is
never readable.

**Who is told** (`course_alert` notification, `20271124002408`): runners
with an active or paused plan aimed at the race, and runners who saved its
linked course; for a route alert, its savers and runners training for an
upcoming race on it. Never the author, never for a past race, one notice
per alert, at most five alerts per target per day. Email and push link to
`/course-alerts/{id}`, which opens the race or route. Mute:
`notify_course_alert` (web Settings → Notifications).

**UI.** Web `CourseAlerts.svelte` on `/races/[id]` and `/routes/[id]`;
mobile `CourseAlertsSection` on `RaceDetailScreen` and club routes'
`RouteDetailScreen`. The organiser club's admins get the form and a
Remove button held for the undo window.

## Tests

- pgTAP: `race_listing_provenance_test.sql` (derived flag, revoke / hide /
  private, a runner cannot forge it, the search column),
  `course_alerts_test.sql` (who may post and remove, who is told, reads,
  revoke, rate limit), `notifications_kind_allowlist_test.sql`.
- Pair: `social/provenance.test.ts` ↔ `test/provenance_test.dart`.
- Playwright: `tests-e2e/races/race-provenance.spec.ts` (card + detail
  badges, revoke, post / resolve / remove an alert, not-found resolver).
- Flutter: `race_detail_screen_test.dart`, `races_screen_test.dart`,
  `club_detail_screen_test.dart`, `push_target_test.dart`.
- Go: `notification_course_alert_test.go`, `mailer_test.go`.

## Not yet

- Ranking fan copies below official listings on the calendar (discovery
  slice).
- A verified club can still claim a race it does not organise; the
  verification-request review is where that tightens.
- The gym routine detail badge on mobile.
