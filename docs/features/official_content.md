# Official content: verified organisers

The spec for issue #1190, "Official content". This document covers the **verified organiser** model and the **verification request flow** that has shipped. The race-course slice (claiming a race listing, linking its course) is in [race_calendar.md](race_calendar.md) (#1297, decisions § 2381); heatmap and discovery ranking is in [api_database.md § Discovery RPCs](../backend/api_database.md); the seeded official content is under *Seeded official content* below; the onboarding import step is tracked on the issue.

## The trust model

- **The verified club is the unit of trust.** Threkir's own official account is an ordinary verified club with no special case in code.
- **"Official" is derived, never stored per row.** A route, plan, gym routine, challenge or session plan is official when its `club_id` names a verified, public, unhidden club and its author is an active owner or admin of that club (`private.is_official_publisher`, migration `20271021000030`, decisions § 2228). Revoking the club's badge removes it from everything at once.
- **Featured is separate.** `routes.is_featured` is a Threkir editorial pick from anyone; official is publication by the verified organiser.
- **Verification is free and can never be bought.** There is no member-count threshold, so a new official organiser can verify on day one.

## Verification requests (migration `20271120000004`, decisions § 2398)

### Who does what

| Actor | Can |
|---|---|
| Club owner | Submit a request, prove the domain (check DNS / file, send the email link), withdraw a pending request |
| Club admin | See the club's requests and status (read-only) |
| Site admin (`app_admins`) | See the queue, approve, reject with a reason, revoke a badge with a reason, read a club's history |
| Anyone with the mailed link | Confirm the email proof |

### The request

The owner opens the **Official verification** card on the club page (`ClubVerificationCard.svelte`, rendered for the owner and admins), names the organisation the club officially represents and optionally adds a note for the reviewer. The **claimed domain is the host of the club's website link** (`private.club_website_domain`: lower-cased, scheme, credentials, port, path and one leading `www.` removed; an IP literal is refused). A club with no website is asked to add one in Edit club first. One request can be live per club (a pending application or the approval in force), and each request gets its own random 128-bit token.

### Proof (any one)

| Method | What the owner publishes | Checked by |
|---|---|---|
| DNS TXT | `threkir-verification=<token>` at `_threkir-verification.<domain>` (or the apex) | `club-verification` Edge Function, "Check now" |
| `.well-known` file | `https://<domain>/.well-known/threkir-verification` with `threkir-verification=<token>` (or the bare token) on a line of its own | `club-verification` Edge Function |
| Email | Nothing: the owner names the part before the @ (`hostmaster`, `info`, …) and a one-time link goes to that address at the domain | the `club_verification_email` job; confirmed at `/club-verification/confirm` |
| Manual review | Anything a reviewer can check by hand (a link to the club from the official site or socials) | the reviewer, who must write a note |

The Edge Function reads DNS over HTTPS and fences the file fetch against SSRF (https and port 443 only, the claimed domain or its `www.` only, every hop's addresses screened, no automatic redirects, one deadline, a 4 KiB cap). The fence and its one accepted residual are decisions § 2399.

The email link carries a 192-bit token in the URL fragment, single use, valid 24 hours; the database keeps only its SHA-256. The landing page confirms on a click, never on load. Three emails a request a day at most.

A found proof is recorded on the request (`proof_method`, `proof_verified_at`, `proof_detail`). It does not verify the club.

### Review

`/admin/club-verification` lists **Pending**, **Verified** (every verified club, including ones verified before requests existed) and **Closed** (rejected, revoked, lapsed, withdrawn in the last 180 days). Each row shows the organisation, the domain, the club website, the owner, the proof found, the club's note and a reminder to check for lookalike domains. Every action is behind a dialog:

- **Approve**: needs the club's website still on the requested domain; a note is required when no automated proof was found (recorded as `manual`). Sets `clubs.is_verified`.
- **Reject**: a reason the owner reads on the card.
- **Remove badge** (revoke): a reason the owner reads; works by club, so it also removes a badge granted before requests existed.
- **History**: the club's audit log.

Each status change notifies the club's owner and active admins (`club_verification`, in-app, push and email), with no reviewer named.

### Keeping the badge honest

- **Lock.** Renaming a verified club, changing its slug, or moving its website to another domain drops the badge until it is reviewed again (`clubs_verification_lock`). The owner is warned in Edit club.
- **Re-check.** Hourly, `club-verification-recheck` re-runs the DNS and file checks for clubs approved on them, each about once a day. Three failures in a row drop the badge and mark the request lapsed (`proof_missing`), which notifies the club; the owner can request again. Clubs proven by email or manual review are not re-checked. Arming the schedule is one line in [`apps/backend/ops/prod_config.json`](../../apps/backend/ops/README.md) (`"club_verification_recheck"` under `cron_urls`), which the next backend release applies and verifies; see [deployment.md](../ops/deployment.md).

### Audit and data

`club_verification_audit` records submit, withdraw, email sent, proof found, re-check failed, approve, reject, revoke and lapse, with the actor (null for the system) and a snapshot of the club name. It is append-only. The requests a user submitted and the actions they took are in both data exports. Schema, RLS and RPCs: [api_database.md § Club verification RPCs](../backend/api_database.md).

### Platforms

Web is the whole flow. Mobile (Android and the iOS twin) shows the owner and admins a read-only status card on the club screen and points to the web; the request and review are web-only by decisions § 24. The notification opens the club on every platform.

## What the badge lends

The provenance labels (official / verified source / traced / community) on content, race listings and their courses, and organiser course alerts, are specified in [provenance.md](provenance.md) (decisions § 2406 / § 2407).

## Name disputes (migrations `20271202000001`..`004`, decisions § 2441)

A fan club can take "Comrades Marathon" and keep it, and a copied plan or course can sit beside the real one. The verified organiser now has a way to say so, through the existing report flow.

### Filing

An active owner or admin of a verified, public, unhidden club opens **Report as your organisation** on a club, a public route, a plan or routine in the public library, a public challenge, or a race listing another club has claimed. They pick the club they speak for (when they run more than one), say what is copied, and send. `submit_organiser_dispute` is the gate (`private.is_official_publisher`, the same derivation as "official"), so an unverified club, a plain member or anon is refused at the database, not just hidden in the UI. The report lands in `reports` with reason `organiser_dispute` and `organiser_club_id`. The general `submit_report` refuses that reason. An organiser cannot dispute its own club, its own content, or content it cannot have seen (a private plan, an unclaimed race, which it can simply claim). Filing shares the general report's rate limit (10 an hour) and its one-pending-report-per-target rule, and notifies nobody.

### No automation

A dispute never hides anything by itself, however many verified organisers file one: the auto-hide trigger skips it and the vetted-reporter count leaves it out, so disputes never tip a general report over the threshold either. A person decides, as in the verification review (§ 2398).

### Review

Disputed targets sort first on `/admin/reports`, with an **Organiser dispute** badge, the reporting clubs (and whether each is still verified), and any rename deadline. The detail panel offers, each behind a confirm:

| Action | What happens |
|---|---|
| **Hide** (`takedown`) | A club or route gets `shadow_hidden`, the same hide auto-hide uses. A library plan or routine and a challenge are unpublished, and a trigger refuses republishing that row until an admin restores it. A race listing's claim is released (organiser club, course link and course stamps cleared) so the rightful organiser can claim it. The dispute reports are marked reviewed. |
| **Send rename notice** | The owner is asked to rename or change it within a deadline (14 days by default, 1 to 60). The reports stay pending and the target stays at the top of the queue showing the deadline. Nothing happens automatically at the deadline; the reviewer then hides or dismisses. |
| **Dismiss dispute** | The dispute reports are dismissed and nothing changes. |

Only the dispute reports are touched, and the general Dismiss / Mark reviewed buttons now leave dispute reports alone, so a dispute closes only with its log entry and its notices. **Restore** (`admin_unhide_target`) lifts a plan, routine or challenge takedown; the owner republishes when they choose. A library plan is published as a new copy, so while a copy's takedown stands its source plan cannot be published again either; content rebuilt from scratch under the same name is a new target, and the organiser files again.

### Audit and notices

Every filing and action is a row in the append-only `organiser_dispute_actions` with the reviewer's id, readable only through admin RPCs. Both sides get an `organiser_dispute` notification (in-app, push and email) naming the reporting club, never the reviewer, and read the outcome on `/disputes`: the owner sees reviewed disputes about their content (with the deadline and the reviewer's note), and the reporting club's owner and admins see their filings and what became of them. Both legs are in the data export.

### Platforms

Web is the whole flow. On Android and iOS the report sheet on a club or a route adds the dispute reason for a verified organiser, and the notice opens the web disputes page. Plans, routines, challenges and race listings have no report menu on mobile, so they are disputed from the web.

## Seeded official content (migrations `20271211000001`..`004`, decisions § 2446)

A day-one runner finds the shared libraries nearly empty. The official Threkir club (`threkir`, committed in `scripts/parks/publisher.json`) publishes a starter set through a catalogue in the repo, loaded on every backend release the way park courses are ([park_courses.md § Loading courses](park_courses.md)).

### The catalogue

`scripts/official/catalogue/<kind>/<slug>.json`, one file per item, named by its slug:

| Kind | Starter set | Published as |
|---|---|---|
| `plans` | Walk-run to 5K (9 weeks) | a public library plan owned by the club, read as official |
| `gym_routines` | Strength for runners: lower body; Strength for runners: no equipment; Mobility for runners | a public library routine owned by the club |
| `challenges` | Run 50 km / Run 100 km / 12 runs / Climb 1,000 m running / Run 3 Virginia park courses, each month; Run 1,000 km, each year | one public individual board per month or year |
| `race_courses` | none (see the gate below) | a public club route, the race claimed and linked as `traced` |

There are no standalone segments: a catalogue segment needs reviewed geometry, and the park pipeline (`scripts/parks/`) is the one place that builds and reviews it, so official segments keep arriving as park courses.

- **The 10K and half-marathon plans are held back.** Built with no goal time or recent race, `generatePlan` peaks the half's long run at 8 km and makes every interval day 10 km, longer than that week's long run; the 10K plan has the same shape. Official plans wait for the generator's no-anchor progression to be fixed; adding them is then a preset each.
- **Plans are generated, not hand-written.** Each plan file carries the `preset` it was built from (goal, weeks, days per week, walk-run) and its weeks are what `generatePlan` builds from it, projected the way the library stores a copy (§ 2340): no paces, notes, race names or HR targets, a duration beside a distance dropped, on the reference week of 2001-01-01 so a clone shifts it to the runner's start. A timed walk-run session keeps its time rather than the distance the fallback pace estimates. `apps/web/src/lib/training/official_plan_catalogue.test.ts` fails when the weeks no longer match the generator; regenerate with `OFFICIAL_PLANS_WRITE=1` (the command is in its header) and review the diff.
- **Routines** use the exercise catalogue's names where it has the lift and plain names otherwise, with no loads: the notes say to pick a load that leaves two or three reps in reserve and to stop anything that hurts. No item makes a health claim.
- **Challenges recur.** The schema has no recurring challenge, so each item names a `recurrence` (`monthly` or `yearly`, in UTC) and a title with `{period}`; every load publishes the current period and every period starting within the next 45 days as its own board (`<slug>@2026-12`, `<slug>@2027`), so a quiet month between releases loses nothing. A period more than half over is not opened late. Once a board's window has started its terms (title, metric, goal) are frozen, so nobody's goal moves mid-month; a change reaches the next board. An official board stays in Browse before anyone joins it (§ 2228's derivation, exempt from the seven-day dead-board rule).
- **Park passport boards** (`metric: "park_courses"`) carry a `park_region_code`, an ISO 3166-2 code such as `US-VA`: required for that metric and refused on every other, by the catalogue check and again by the load (migration `20271214131301`). The board counts distinct park courses completed in that region's active parks. A region is part of a board's terms, so it freezes with them once the window opens. **The monthly passport is committed** (issue #1343): `challenges/virginia-park-courses-a-month.json`, "Run 3 Virginia park courses in {period}", a goal the six open Pocahontas courses can meet in a month. **The yearly one is not:** "Run 10 Virginia park courses" could not be finished with six. When enough courses are loaded for an honest goal, add `challenges/virginia-park-passport.json` (the shape is in `scripts/official/lib/fixtures/virginia-park-passport.json`, which the catalogue tests read) with a goal no higher than the number of open courses in the region, and preview the release with `dry_run`.

`scripts/official/lib/official_catalogue.mjs` checks every item against the database's constraints (its value lists are rails of `check_constraint_unions.mjs`; the plan enums are compared with `database.types.ts`), so a bad item fails the PR, not the release.

### The load

The "Sync production state" step of `release-backend.yml` runs `scripts/official/sync.mjs`'s stage last, after the park catalogue and the prod config (so a flag the same release turns on is the one it reads). It resolves the author with `private.resolve_club_publisher` and calls `private.load_official_catalogue` once, which:

- refuses unless the author is an active owner or admin of the verified, public, visible club;
- keys every item by `private.official_catalogue_items (kind, slug)`, a service-role-only crosswalk, so no client can forge a slug onto its own row; a row deleted in the app is recreated on the next load;
- compares before it writes (a plan's weeks and a routine's exercises as a whole design), so an unchanged catalogue reports every item `unchanged` and writes nothing;
- **retires, never deletes**: a plan or routine the catalogue drops is unpublished and detached from the club (author-private, so it leaves the club's templates as well); a dropped challenge's open boards are made private, so their entrants keep them; each is reported `retired` once, and naming it again republishes it;
- leaves a row taken down after a naming dispute (§ 2441) alone and reports it `held`;
- re-authors every live row when the club's owner changes, so it stays official.

Preview a change with a Release Backend `workflow_dispatch` (`dry_run` on): the step summary lists each item's action and rolls back. Fallback if the workflow cannot run: `node scripts/official/sync.mjs [--dry-run] > official.sql`, then `psql` on the service-role connection.

The public gym routine library could not hold an official row before this: a public template had to be club-free (`gym_routines_public_not_club`). That rule is now a trigger that holds it for client writes only, `public_gym_routines` carries `is_official`, and both platforms show the badge in the library list and preview. A club admin publishing their own club's plan or routine to the library from the app is still not built.

### Race courses: off until counsel and real geometry

The catalogue format takes a race course (`race_courses/<slug>.json`): the race by `listing` (`provider` + `provider_race_id`) or `listing_id`, the traced line (`waypoints`), `distance_m`, `surface`, a `description` that says what it was traced from, and `source_ref`, the https URL of the published course map. The load creates or updates a public club route, claims the race if no club has (one another club has claimed reports `claimed_elsewhere`; an unlisted race reports `missing_listing`), and links it as `traced`, so the race page reads "Course drawn by Threkir from the race's published map". A race whose organiser already linked its own `official` course is left alone (`course_exists`). A dropped course's route is made private and unlinked.

None of that runs while the `official_race_courses` flag is off, which is how `20271211000001` seeds it: each course item reports `gated`. Turning the flag off after courses have loaded retires them (route private, race unlinked), so the gate also takes them down. The catalogue holds no course, and none may be invented: the line must be a reviewed trace.

**Pre-deploy checklist (race courses):**

- [ ] Owner's counsel check that tracing a course from an organiser's published map, and claiming the race as the Threkir club, is acceptable (issue #1190).
- [ ] A real, reviewed GPX per course, committed as its `race_courses/<slug>.json` with the map's URL in `source_ref`.
- [ ] Then turn the flag on in `apps/backend/ops/prod_config.json` (`feature_flags.official_race_courses`, with the sign-off link), and preview the release with `dry_run` first.

## Not built yet

- Trusted verifiers (a federation verifying its member races) — later, not v1.
