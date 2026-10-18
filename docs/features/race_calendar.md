# Race calendar + results import — implementation plan

> **Status:** Shipped 2026-06-20 (migration `20270214_001`). This page began as the implementation handoff plan; the calendar, the `race-results-import` / `race-listings-sync` Edge Functions, the auto-match-on-record seam, and manual paste are live on web + mobile. **Provider legs:** parkrun shipped; **RunSignUp** is keyless end to end since 2026-10-14 — its results leg resolves the listing day's events and imports by bib against the real feed ([decisions § 1903](../architecture/decisions.md)), its listings leg reads the public `GET /Rest/races` feed, a five-minute `race-listings-sweep` fills the calendar one state-window at a time once its Vault secret is armed ([§ 1902](../architecture/decisions.md)), and each synced race is placed on the map from its ZIP ([§ 1901](../architecture/decisions.md)); both readers are pinned against recorded live payloads ([integrations.md § RunSignUp](integrations.md#runsignup)); the **ChronoTrack** leg is built fail-closed behind `CHRONOTRACK_CLIENT_ID`/`CHRONOTRACK_USER_ID`/`CHRONOTRACK_PASSWORD` (both return `503 provider_not_configured` until provisioned, with a per-provider Settings card explainer); the **UltraSignup** leg was built the same way behind `ULTRASIGNUP_API_KEY`/`_SECRET` and, since 2026-08-30, reached mobile too (**since 2026-10-13 it is keyless, imports by a person the runner links in Settings plus an `event_distance_id` + date match, is opted in with `ULTRASIGNUP_RESULTS_ENABLED`, and reaches mobile through the same person flow since 2026-10-14** — [decisions § 1841](../architecture/decisions.md), [integrations.md § UltraSignup](integrations.md#ultrasignup)) — all three providers now carry a Settings tile and a reachable import path on the phone, generated from one catalogue rather than branched on by name. **parkrun events** (the weekly 5k and junior runs, dated to their next run day and placed at the feed's own point) are built into the same sync and sweep behind `PARKRUN_EVENTS_ENABLED`, **off by default** until parkrun gives written permission ([decisions § 1958](../architecture/decisions.md), [integrations.md § Upcoming parkruns](integrations.md#upcoming-parkruns)). RaceResult per-site scraping stays a scoped follow-up. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value

Parity backlog item #10: let a runner **discover races near them** (a searchable calendar of upcoming races with date, distance, location, and an **entry/registration link**), and **auto-match a recorded run to its official race result** so the chip time, place, and splits land on the run automatically. Today the only race-adjacent surfaces are club *events* (intra-club) and the parkrun scraper (one provider, manual athlete-number entry). This adds a first-class, cross-provider **race calendar** plus a **results-import + auto-match-on-record seam** that works for RunSignUp (built behind a missing-API-key gate, per `docs/features/integrations.md`) and parkrun (already shipped), and degrades to manual paste for everything else.

## What already exists to build on (verified)

- **`docs/features/integrations.md § Race results (RunSignUp + general scraping)`** — the design source. RunSignUp REST API (`GET runsignup.com/Rest/race/{race_id}/results/get-results`, API-key gated), parkrun scrape (shipped), general timing-platform URL patterns (ChronoTrack / RaceResult / UltraSignup), and the **race `external_id` format `race:{race-name}:{date}:{bib}`** + `source = 'race'`.
- **`apps/backend/supabase/functions/parkrun-import/index.ts`** + its `lib.ts` — the **exact pattern to mirror** for a race-results importer EF: auth-before-parse, per-user tiered rate limit (`checkRateLimitTiered`), `readJsonWithLimit` / body caps, `withSentry`, fail-loud on non-2xx upstream, `privacy_default`-honouring `is_public`, upsert with `onConflict: external_id`, cap helpers in `lib.ts`.
- **`runs` table + metadata race fields** — `docs/backend/metadata.md § Race fields` **already reserves four owner-only keys with no writer**: `race_name`, `bib`, `overall_place`, `chip_time` (all stripped from `public_runs` by `20260714_001`). This plan **builds the writer**. The additional keys this plan introduces — `gun_time`, `age_group_place`, `age_group` — are **NOT yet in the registry**; this plan must add a registry row for each (same owner-only classification + `public_runs` strip) in the same turn it writes them, per the metadata-key registry rule. `runs.source` CHECK already includes `'race'` (`20260505_001_narrow_union_check_constraints.sql`).
- **`runs.external_id`** unique-per-user index → dedupe via `ON CONFLICT (external_id) DO NOTHING` (the cross-source dedup strategy in integrations.md).
- **`integrations` table** + `IntegrationProvider = 'strava' | 'garmin' | 'parkrun' | 'runsignup'` (`apps/web/src/lib/types.ts:151`, CHECK in `20260505_001`) — **`runsignup` is already a permitted provider**. OAuth-style connect rows live here.
- **`apps/web/src/routes/settings/integrations/+page.svelte`** + the mobile `settings_integrations_screen.dart` — where a "Connect RunSignUp" / "Import race results" card belongs (the parkrun card is here).
- **Discover surface precedent** — `apps/web/src/routes/social/+page.svelte` + `apps/web/src/lib/components/SocialDiscover.svelte` + the `search_public_events` RPC (`20270110_001`, with `pg_trgm` discipline index, proximity via `clubs.location_point` + `p_center_lng/lat/radius_m`, `geocodePlace` in `apps/web/src/lib/routes/geocoding`). The race calendar's discovery UI **directly mirrors `SocialDiscover`** (category/place/time filters, "near me" geolocation).
- **Run save path** — `packages/run_recorder/lib/src/run_recorder.dart` (recorder state machine) and `packages/api_client/lib/src/api_client.dart` (`upsertRun*`, `onConflict: RunRow.colExternalId`) — where the auto-match-on-record seam hooks in (post-save, layered-resilience-wrapped).
- **Run-detail** `apps/web/src/routes/runs/[id]/+page.svelte` + mobile `apps/mobile_android/lib/screens/run_detail_screen.dart` — where a matched race result + "Find my result" affordance render.

## Data model / migrations

One migration. **Number is a placeholder — assign the next free sequential number at landing** (e.g. `2027XXXX_001_race_calendar.sql`; latest on `main` at spec time is `20270202_001`). The fundraising plan also wants the next slot, so coordinate so the two don't collide.

Two new tables: `races` (the calendar) and `race_results` is **already taken** by clubs (`20260424_001_event_results.sql` defines `event_results`, and there is no top-level `race_results`). Use **`race_listings`** for the calendar and **`race_result_imports`** for raw imported provider results — but the simplest durable design reuses the existing `runs` row as the result store (the integrations.md design maps a result straight onto a `run` with `source = 'race'`). So:

- **`race_listings`** — the discoverable calendar (one row per real-world race).
- **No separate results table** — an imported/auto-matched result is **written onto the runner's `runs` row** (`source = 'race'`, `external_id = race:{...}`, the metadata race fields that already exist in the registry). This avoids a parallel results entity and reuses the dedup index + privacy strip already built. A nullable `runs.race_listing_id` FK links a matched run back to its calendar entry (mirrors `runs.event_id`).

```sql
-- ── race_listings (the calendar) ─────────────────────────────────────────────
create table race_listings (
  id              uuid primary key default gen_random_uuid(),
  provider        text not null,              -- RaceProvider union (below)
  provider_race_id text,                      -- e.g. RunSignUp race_id; null for manual
  name            text not null,
  race_date       date not null,
  distance_m      integer,                    -- nominal distance; null if unknown/multi
  location_label  text,                       -- "Boston, MA"
  location_point  geography(point, 4326),     -- for proximity search (clubs.location_point precedent)
  entry_url       text,                       -- registration link (http/https CHECK)
  results_url     text,                       -- where results live, when known
  submitted_by    uuid references auth.users on delete set null,  -- crowd-submitted listings
  is_verified     boolean not null default false,  -- admin/provider-verified vs user-submitted
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table race_listings add constraint race_listings_provider_check
  check (provider in ('runsignup', 'parkrun', 'manual', 'chronotrack', 'raceresult', 'ultrasignup'));
alter table race_listings add constraint race_listings_entry_url_scheme_check
  check (entry_url is null or entry_url ~* '^https?://');
alter table race_listings add constraint race_listings_results_url_scheme_check
  check (results_url is null or results_url ~* '^https?://');

-- one listing per provider race; manual listings dedup loosely on (name,date)
create unique index race_listings_provider_uniq
  on race_listings (provider, provider_race_id) where provider_race_id is not null;
create index race_listings_date_idx on race_listings (race_date);
create index race_listings_location_gist on race_listings using gist (location_point);
create index race_listings_name_trgm
  on race_listings using gin (name extensions.gin_trgm_ops);  -- pg_trgm, like events_discipline_trgm

alter table race_listings enable row level security;

-- Public read (a race calendar is public discovery data). Anyone, incl. anon.
-- SUPERSEDED by 20270320_001: the base-table SELECT is now submitter-own-rows
-- only and the public calendar is served by the redacted public_race_listings
-- view (every column except submitted_by) — using(true) let anon read the
-- submitted_by user-id crosswalk. search_race_listings + the client/EF
-- listing lookups read the view.
create policy "race listings readable by all"
  on race_listings for select using (true);
-- Authenticated users may submit a listing (is_verified stays false until an
-- admin/import verifies). A trigger forces is_verified = false on user INSERT.
create policy "users submit race listings"
  on race_listings for insert to authenticated with check (submitted_by = auth.uid());
-- Submitter may edit their own unverified listing; verified ones are locked.
create policy "submitters edit own unverified listings"
  on race_listings for update to authenticated
  using (submitted_by = auth.uid() and is_verified = false)
  with check (submitted_by = auth.uid() and is_verified = false);

-- ── runs linkage ─────────────────────────────────────────────────────────────
alter table runs add column race_listing_id uuid references race_listings on delete set null;
create index runs_race_listing_idx on runs (race_listing_id) where race_listing_id is not null;
```

**The proximity + soonest-first discovery RPC** (copy `search_public_events` from `20270110_001`, `security invoker`, public-scoped):

```sql
create or replace function search_race_listings(
  p_query    text default null,    -- name ILIKE / trgm
  p_distance text default null,    -- '5k' | '10k' | 'half' | 'marathon' | 'ultra' (band → metres range)
  p_from     date default null,    -- date window
  p_to       date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default null,
  p_limit    int  default 60
) returns table (... race_listings cols + distance_m_away ...) ...
```

**Two narrow unions** (TS union + CHECK in lockstep; append to `apps/web/scripts/check_constraint_unions.mjs` `PAIRS`):

```
RaceProvider = 'runsignup' | 'parkrun' | 'manual' | 'chronotrack' | 'raceresult' | 'ultrasignup'
RaceDistanceBand = '5k' | '10k' | 'half' | 'marathon' | 'ultra'   (client-side only — derived; no CHECK column unless persisted)
```

Note: `runs.source = 'race'` and the metadata race fields are **already in the schema/registry** — no change needed there beyond writing values. `race_listing_id` is a new real column → both type generators run.

**Two codegen commands (mandatory):**

```
cd apps/backend && npm run gen:types
dart run scripts/gen_dart_models.dart
```

**`public_runs` strip**: `race_name`/`bib`/`overall_place`/`chip_time` are already stripped (`20260714_001`). The new `runs.race_listing_id` column is **non-sensitive** (it just links to a public calendar entry) — confirm it passes through the `public_runs` projection or add it to the denylist in this migration if owner-only is preferred (recommend: pass-through, it reveals nothing the public results page doesn't).

## Web implementation (canonical)

Web-first (`decisions.md §24`). Paths under `apps/web/src/`.

**Edge Functions (new, under `apps/backend/supabase/functions/`):**
- `race-results-import/index.ts` + `lib.ts` — **mirror `parkrun-import` closely.** Two modes by `provider`:
  - `runsignup` — keyless (the key pair is sent only when both halves are set, decisions § 1903): read the race's events from `GET /Rest/race/{id}`, take the in-person running events run on the listing's date (listing distance first), and ask each `get-results?event_id=…&bib_num=…` until one answers; an HTTP-200 error envelope is a `502`. Map the row (`bib`, `place`, `chip_time` → `clock_time`, hundredths rounded up, the age group from the one placed division whose name is an age band (decisions § 1913), and, when no age group is placed, the one award division — masters, overall top N, weight class — as `division_award` + `division_award_place` (decisions § 2086)) to a `run` row (`source='race'`, `external_id=race:{name}:{date}:{bib}`, metadata `race_name/bib/chip_time/gun_time/overall_place/age_group_place/age_group/division_award/division_award_place`, `distance_m` from the event that answered, else the listing). Per-user `external_id` dedup. Honour `privacy_default`.
  - `paste` / `general` — accept a results URL or bib+race; for the v1 the durable path is **structured paste** (the user pastes their result row from a non-API timing site) rather than a brittle per-site scraper. Build the scraper hooks (URL-pattern dispatch in `lib.ts`) and ship the RunSignUp + **UltraSignup** + paste paths; ChronoTrack / RaceResult per-site scrapers stay scoped follow-ups (the integrations.md fragility warning). **UltraSignup leg shipped (2026-06-20, decisions §185)** — the RunSignUp pattern with its own `ULTRASIGNUP_API_KEY` / `ULTRASIGNUP_API_SECRET` fail-closed gate (unset → 503 `provider_not_configured`), `extractUltraSignUpResults` in `race-results-import/lib.ts`, the `race-listings-sync` per-provider probe, a Settings integrations card + web data-layer surface; 20 lib tests + a Playwright fail-closed-gate e2e.
  - Pure parsing/mapping (`mapRunSignUpResult`, `parseRaceResultRow`, field caps) lives in `lib.ts` for unit testing without network.
- `race-listings-sync/index.ts` — pull upcoming RunSignUp races into `race_listings`, optionally scoped by `near: { postal_code, radius_m }` (RunSignUp searches by US ZIP + radius only; a point hint is refused). **Keyless since 2026-10-14**: the feed is public and `RUNSIGNUP_API_KEY`/`_SECRET` are sent only when both are set. One listing per RunSignUp race, distance from its longest in-person running event, drafts / private / virtual-only / walk-only races excluded, and so is a race the feed dates `null` on both `next_date` and `last_date` (an ongoing virtual challenge — decisions § 2081), so `unusable` keeps meaning the feed's shape moved. The feed has no coordinates, so each race is placed from its US ZIP through `us_zcta_points` (Census 2024 Gazetteer ZCTA internal points, migration `20270805000001`, decisions § 1901), which puts it inside the proximity gate in `search_race_listings` and the auto-match seam below; a ZIP with no ZCTA writes the race without a point, counted `unplaced`. The UltraSignup leg of the same function stays gated on `ULTRASIGNUP_API_KEY`/`_SECRET`. The **parkrun** leg (`provider: 'parkrun'`, decisions § 1958) reads parkrun's public events file, needs a point hint (`near: { lng, lat, radius_m }`, filtered here because the file is global), dates each event to its next Saturday 5k / Sunday junior run in its own zone, and places it at the feed's coordinates; it answers `503 provider_not_configured` unless `PARKRUN_EVENTS_ENABLED=true`.
- `race-listings-sweep/index.ts` — the scheduled filler (decisions § 1902): pg_cron `race-listings-sweep` every five minutes → `invoke_race_listings_sweep()` → pg_net POST with the `CRON_SECRET` bearer, only when the Vault secrets `race_listings_sweep_url` + `cron_secret` exist (migration `20270805000002`). Each run reads one state over one 14-day window (the slot derived from the clock, 51 jurisdictions x 6 windows = a full 84-day pass every 25.5 hours), one keyless request, and writes through `race-listings-sync/write.ts`. Nine slots a cycle (one every 34) also read parkrun's events file and write one ninth of it by event id, so every parkrun listing is re-dated once a cycle; with `PARKRUN_EVENTS_ENABLED` unset they make no parkrun request and answer `parkrun: { enabled: false }`.

**`data.ts` helpers (`apps/web/src/lib/core/data.ts`):**
- `searchRaceListings(filters)` → `RaceListingResult[]` (calls `search_race_listings`; mirror `searchPublicEvents` exactly, incl. `geocodePlace` center + geolocation).
- `submitRaceListing(input)` / `updateRaceListing` — crowd-submitted calendar entry.
- `importRaceResult({ provider, listingId, ... })` → invokes `race-results-import`.
- `fetchRaceResultForRun(runId)` → reads the run's race metadata + linked listing (for run-detail render).
- `findRaceMatchCandidates(runId)` → the auto-match seam (below): given a run's `started_at` + GPS start point + distance, return nearby same-day `race_listings` to offer "Is this your race?".

**types.ts overlays:**
- `RaceProvider` union; `RaceListing = Omit<RaceListingRow, 'provider'> & { provider: RaceProvider }`; `RaceListingResult` (RPC projection with `distance_m_away`).

**Routes / components (new):**
- `apps/web/src/routes/races/+page.svelte` + `+page.ts` — the **race calendar / discovery** page. **Reuse `SocialDiscover`'s structure**: name search, distance-band chips, date window, "near me / near a place" (geolocation + `geocodePlace`), result cards (name, date, distance, location, "X km away", **Register** link to `entry_url`, **Import my result** when results are available). A "Submit a race" affordance for crowd listings.
- `apps/web/src/lib/components/RaceCalendarCard.svelte` — a discovery result card.
- `apps/web/src/lib/components/RaceListingEditor.svelte` — submit/edit a manual listing.
- **Settings → Integrations** `apps/web/src/routes/settings/integrations/+page.svelte` — add a **RunSignUp card** ("Connect to import race results"; disabled with an explainer when `RUNSIGNUP_API_KEY` is unconfigured server-side — surface via a `503` probe) and keep the existing parkrun card.
- **Run-detail** `apps/web/src/routes/runs/[id]/+page.svelte` — if the run has race metadata, render the official result (chip time, place, race name, link to the listing). If not, an owner-only **"Find my race result"** button that runs `findRaceMatchCandidates` → pick a listing → `importRaceResult` (or manual paste).

**Nav placement (web)**: add `/races` to the primary discovery nav alongside `/social` and `/routes` (web has no 6-tab limit). The legacy-free top-level `/races` is the canonical URL.

## The auto-match-on-record seam (the load-bearing piece)

When a run finishes recording, offer to match it to an official race result — **never auto-write silently** (data-trust "inform" tier, `multi_modal.md §63`):

1. **After local save** (post `run_recorder.stop()` + upsert), a **best-effort, fire-and-forget, try/catch-wrapped** check (layered resilience — an auxiliary L4 effect that must never break the L0/L1 save): does a `race_listings` row exist with `race_date == run.started_at::date` **and** `location_point` within ~5 km of the run's start point **and** a distance band matching the run's distance? This is the pure predicate `raceMatchScore(run, listing)` (parity pair, below).
2. If a candidate is found, surface a **non-blocking prompt** on the run-detail / post-run summary: *"Was this the {race name}? Import your official result."* — the user confirms; nothing writes to their run's race metadata without that tap.
3. On confirm → `importRaceResult` fetches the official result (RunSignUp by bib, or manual paste) and stamps `race_name/bib/chip_time/overall_place` + `race_listing_id` onto the **existing** run row (not a new run — dedup: the recorded run already exists; the import enriches it, matched on the same `external_id`-or-run-id, so a later provider sync via `external_id` doesn't create a duplicate).
4. **Dedup invariant**: a run recorded in-app (`external_id = app:{uuid}`) that is later matched to a race must not also produce a second `race:{...}` run. The match writes onto the in-app run and sets `race_listing_id`; the importer's `onConflict` path is only for results with **no** recorded counterpart (a runner who didn't record but wants the result).

## Mobile implementation (Android + iOS twin)

Byte-identical across `apps/mobile_android/lib/` and `apps/mobile_ios/lib/` (+ tests), `decisions.md §39`.

- **Service** `apps/mobile_android/lib/` — add a `race_service.dart` (or extend an existing service) with `searchRaceListings`, `importRaceResult`, `findRaceMatchCandidates`, `fetchRaceResultForRun`.
- **Discovery screen** `apps/mobile_android/lib/screens/races_screen.dart` — mirrors the web calendar (search, distance chips, near-me, register link via `url_launcher`). **Reuse, don't grow the bottom nav**: surface Races as an entry inside the existing Social area (where Clubs / Discover already live as sub-tabs) or the Fitness-hub "Runs" area — **do not add a new bottom-nav destination** (the shell is a hard 4 nav tabs + centre Log FAB = 5 slots; clubs is a sub-tab of Social, not its own slot — see `apps/mobile_android/CLAUDE.md` + `decisions.md §63`). Place it as a sub-route reachable from the existing discovery surface.
- **Auto-match prompt** — the post-run summary / `run_detail_screen.dart` shows the non-blocking "Was this the {race}? Import result" card when `findRaceMatchCandidates` returns a hit. The recorder-side seam lives in the shared `packages/run_recorder` only as data (it does not call network); the network check runs in the app layer after save, `tester.runAsync`-friendly and try/catch-wrapped.
- **Settings → Integrations** `apps/mobile_android/lib/screens/settings_integrations_screen.dart` — one tile per credential-gated provider, whose copy discloses whether THAT provider's import leg is live. The tiles are generated from `raceImportProviders` (`race_service.dart`) rather than written out, so a leg added to `race-results-import` reaches the phone by being named in that catalogue once; the icon and the four sentences per provider live in `race_provider_labels.dart`, keyed on the same token. Every tile stays tappable whatever its probe says — it is a deep link into the calendar, whose search never needed a key.
- **Import sheet** `showRaceImportSheet` (`races_screen.dart`) is provider-driven, not RunSignUp-only: it probes the provider of the listing it was opened for and offers that provider's pull when configured, that provider's own explainer when not, and manual paste in every case. `parkrun` / `manual` / `raceresult` listings carry no import leg and fall through to paste — correct, not a gap. The scoping input follows `RaceImportScope`: a bib for RunSignUp / ChronoTrack (an unscoped pull returns the whole finisher field, issue #360), and for UltraSignup the person the runner linked under Settings → Integrations (`linkedPerson`, decisions § 1841): the sheet names them and sends them, offers the finder when nobody is linked, and never falls back onto the listing's `provider_race_id`, which holds a race id.
- **iOS twin**: mirror every Dart file + test byte-for-byte.

## TS↔Dart parity helpers

- **`race_match`** — new parity pair: web `apps/web/src/lib/integrations/race_match.ts` ↔ mobile `apps/mobile_android/lib/race_match.dart` (+ iOS twin). Pure: `raceDistanceBand(distanceM)` (metres → `'5k'|'10k'|'half'|'marathon'|'ultra'` with tolerance bands), and `raceMatchScore({ runDate, runStartLatLng, runDistanceM }, listing)` → a 0–1 confidence (same-day + within-radius + distance-band-match), with a threshold above which a candidate is offered. Deterministic, no I/O. **Matched test counts** (≥14 each). Add to the root `CLAUDE.md` lockstep list.
- The RunSignUp JSON→run mapping stays in the EF `lib.ts` (server-only, Deno-tested) — not a parity pair (mobile doesn't import directly; it calls the EF).

## Tests (same commit as each piece)

- **Playwright (`apps/web/tests-e2e/`):**
  - `races/race-calendar-discover.spec.ts` — search by name/distance/near-me; register link present; submit a manual listing.
  - `races/race-result-import-manual.spec.ts` — paste a result onto a run; metadata renders on run-detail; private run keeps race fields owner-only.
  - `races/runsignup-keyless.spec.ts` — with no RunSignUp key (the dev/CI default) the Settings card and the bib-scoped import are offered against the real local function, and a stubbed failing probe still shows the explainer beside paste (decisions § 1903).
- **pgtap (`apps/backend/supabase/tests/`):**
  - `race_listings_rls_test.sql` — anon reads listings; a user can submit (forced `is_verified=false`); cannot edit a verified listing; cannot forge `is_verified`.
  - `race_listing_link_test.sql` — `runs.race_listing_id` FK + the `public_runs` projection still strips the owner-only race metadata.
- **Deno (next to the EF):** `race-results-import/lib.test.ts` + `handler.test.ts` — RunSignUp mapping against the recorded `fixtures/runsignup_{race,results}.json` (event resolution by date, the HTTP-200 error envelope, age group from divisions, hundredths rounded up), keyless with the key sent only when both halves are set, field caps, `external_id` shape, and the issue #360 scoping gates (`runSignUpScopeGate` rejects a request without a bib `400 runsignup_bib_required`; `matchResultGate` rejects an ambiguous enrich `400 ambiguous_match`; `filterResultsByBib` narrows a field to one bib).
- **node:test (web pure):** `apps/web/src/lib/integrations/race_match.test.ts` (≥14).
- **Flutter (`apps/mobile_android/test/` + iOS twin):** `race_match_test.dart` (parity-matched ≥14); `races_screen_test.dart` widget test (search renders, near-me gated); a `run_detail_screen_test.dart` assertion for the auto-match prompt + matched-result render. **Bake in the mobile-test gotchas**: store I/O needs `tester.runAsync`, avoid `pumpAndSettle` on map/cursor animations.

## i18n keys to add (every web locale + all mobile ARBs)

Web `apps/web/src/lib/i18n/locales/{en,de,es,fr,ja,pt-BR}.ts`; mobile `apps/mobile_android/lib/l10n/app_{en,de,es,fr,ja,pt,pt_BR}.arb` (+ iOS twin). Representative:

- `races.title`, `races.searchPlaceholder`, `races.nearMe`, `races.nearPlace`, `races.distance5k/10k/half/marathon/ultra`, `races.kmAway`
- `races.register`, `races.viewResults`, `races.importResult`, `races.submitRace`, `races.unverified`
- `races.findMyResult`, `races.matchPrompt` (`"Was this the {name}? Import your official result."`), `races.matchConfirm`, `races.imported`
- `races.officialResult`, `races.chipTime`, `races.overallPlace`, `races.ageGroupPlace`, `races.bib`
- `integrations.runsignup`, `integrations.runsignupConnect`, `integrations.runsignupUnavailable` (key-unconfigured explainer)

## Docs to update (same turn)

- `docs/product/roadmap.md` — tick item #10 (race discovery + results import), noting RunSignUp gated on the key + per-site scrapers deferred.
- `docs/product/parity.md` — new rows: Race calendar (web ✓ / mobile ✓ / watch ✗); Race results import (web ✓ / mobile ✓ / watch ✗); auto-match (mobile-led, the recording platforms).
- `docs/features/integrations.md` — update the RunSignUp + race-results section from "no writer in source today" to "shipped behind `RUNSIGNUP_API_KEY` gate"; document the `race_listings` table, the import EF, and the auto-match seam.
- `docs/backend/metadata.md § Race fields` — flip the existing four keys' "no writer in source today" notes to point at `race-results-import` as the writer, AND add registry rows for the three new keys (`gun_time`, `age_group_place`, `age_group`) with the same owner-only + `public_runs`-stripped classification. Any new key the importer writes that should stay private must also be added to the `public_runs` strip denylist in this plan's migration (`20260714_001` only strips the original four).
- `docs/backend/api_database.md` — `race_listings` table + RLS + the `runs.race_listing_id` column + `search_race_listings` RPC.
- `docs/architecture/decisions.md` — ADR: *"Race results are stored on the `runs` row (`source='race'`), not a parallel results table; a `race_listings` calendar is publicly discoverable (one `security invoker` RPC, the search_public_events precedent); auto-match-on-record is an inform-tier, layered-resilience-wrapped post-save check that never writes without confirmation; RunSignUp is built fail-closed behind a missing API key, parkrun stays the shipped scraper, per-site scrapers are scoped follow-ups."*
- Root `CLAUDE.md` — add `race_match` to the parity-pair lockstep list.
- `docs/testing/e2e_dev_accounts.md` — add RunSignUp API key to the dev-account checklist.

## Gating / compliance

- **RunSignUp API key is a genuine external blocker** (`integrations.md` says it's blocked on the key) → build the whole code path, gate it fail-closed: `race-results-import` and `race-listings-sync` return `503 provider_not_configured` when `RUNSIGNUP_API_KEY` is unset; the UI card is disabled with an explainer. parkrun + manual-paste paths work without it. This is the "build behind a default-off flag, don't stub" rule. **Superseded for RunSignUp 2026-10-14** (decisions § 1899, § 1903): both its feeds turned out public, so neither function gates it on a key; the one remaining go-live step is arming the sweep's Vault secret (decisions § 1902, `docs/ops/deployment.md`).
- **No paywall gate** by default (race discovery + result import is a free, retention-positive feature) — but if it should be Pro, gate via the existing paywall registry (`paywall.md`), not a stub.
- **Privacy**: imported race results carry owner-only metadata. The four original keys (`race_name`/`bib`/`chip_time`/`overall_place`) are already stripped from `public_runs` (`20260714_001`); the three new keys this plan writes (`gun_time`/`age_group_place`/`age_group`) must be **added to the `public_runs` strip in this plan's migration** (they're not stripped today). The auto-match seam writes only on user confirmation (inform tier). Verify the new `runs.race_listing_id` projection in `public_runs`.
- **Scraping hygiene**: reuse parkrun's politeness pattern (User-Agent env, per-user rate limit, body caps, fail-loud on non-2xx) for any URL-fetch path; per-site scrapers stay deferred to avoid brittle/abusive crawling.
- **parkrun events are gated on parkrun's written permission** (issue #1148 step 1): the whole leg is built and tested, and `PARKRUN_EVENTS_ENABLED` stays unset in every deployment until that permission lands — a deploy-time checklist item in followups.md, not missing code (decisions § 1958). If parkrun asks for attribution, a source label is owed on both card surfaces; neither shows one today.
- **No compliance sign-off gate** (no money, no new PII sub-processor beyond the public results data the runner already published on the timing site) — unlike the fundraising feature.

## Commit plan (ordered, path-scoped)

1. `git commit -- apps/backend/supabase/migrations/20270203_001_race_calendar.sql apps/backend/supabase/tests/race_listings_rls_test.sql apps/backend/supabase/tests/race_listing_link_test.sql` — schema + RPC + RLS + pgtap.
2. `git commit -- apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart apps/web/src/lib/types.ts apps/web/scripts/check_constraint_unions.mjs` — both regenerated type files + unions + PAIRS.
3. `git commit -- apps/web/src/lib/integrations/race_match.ts apps/web/src/lib/integrations/race_match.test.ts apps/mobile_android/lib/race_match.dart apps/mobile_android/test/race_match_test.dart apps/mobile_ios/lib/race_match.dart apps/mobile_ios/test/race_match_test.dart` — parity pair + tests.
4. `git commit -- apps/backend/supabase/functions/race-results-import/ apps/backend/supabase/functions/race-listings-sync/` — import EF (RunSignUp + paste) + sync stub + Deno tests.
5. `git commit -- apps/web/src/lib/core/data.ts` — data.ts helpers.
6. `git commit -- apps/web/src/routes/races/ apps/web/src/lib/components/RaceCalendarCard.svelte apps/web/src/lib/components/RaceListingEditor.svelte apps/web/tests-e2e/races/` — calendar page + components + Playwright.
7. `git commit -- apps/web/src/routes/settings/integrations/+page.svelte apps/web/src/routes/runs/[id]/+page.svelte` + Playwright — RunSignUp card + run-detail result/find-my-result.
8. `git commit -- apps/mobile_android/lib/race_service.dart apps/mobile_android/lib/screens/races_screen.dart apps/mobile_android/lib/screens/run_detail_screen.dart apps/mobile_android/lib/screens/settings_integrations_screen.dart apps/mobile_android/test/... apps/mobile_ios/...` — mobile calendar + auto-match prompt + RunSignUp tile (both twins).
9. `git commit -- apps/web/src/lib/i18n/locales/*.ts apps/mobile_android/lib/l10n/*.arb apps/mobile_ios/lib/l10n/*.arb` — i18n.
10. `git commit -- docs/... CLAUDE.md` — docs sweep.

## Open questions / decisions owed

1. **Calendar seeding** — v1 relies on user-submitted + manual + on-demand RunSignUp import, or do we commit to an auto-sync of RunSignUp's upcoming-races feed (more provider quota, ongoing freshness)? Recommend user-submitted + on-demand first; auto-sync as a follow-up.
2. **Listing trust / moderation** — crowd-submitted listings need a report/verify path (reuse `20270115_001` report-posts infra?) to avoid spam/duplicate listings. How heavy a moderation layer for v1?
3. **Auto-match radius + same-day rule** — is ~5 km from the start point + same date + distance-band the right confidence gate, or do we need bib-aware matching (the user enters their bib once)? Bib entry materially improves RunSignUp matching.
4. **Per-site scrapers** — which timing platform (ChronoTrack? UltraSignup for the ultra persona?) is worth a real scraper next, given the fragility cost?
5. **Mobile placement** — the bottom nav can't grow (hard 4 tabs + centre Log FAB = 5 slots), so Races must live as a sub-route. Confirm the placement: a Social sub-tab (alongside Clubs / Discover) vs the Fitness-hub Runs area.
6. **Migration number collision** with the fundraising plan (both want `20270203_001`) — assign sequentially at landing.

## Sequencing for the implementer

1. Write the race-calendar migration (placeholder name `2027XXXX_001_race_calendar.sql` — assign the next free sequential number at landing; the `20270203_001` used in the commit-plan example is illustrative and collides with the fundraising plan): `race_listings` table + CHECKs + GiST + trgm indexes + RLS + `search_race_listings` RPC + `runs.race_listing_id`, plus the `public_runs` strip additions for the three new race metadata keys. Apply via `safe-migration`.
2. Add `RaceProvider` to `types.ts`; append to `check_constraint_unions.mjs` PAIRS. Run both codegen commands; commit regenerated files. Write + pass pgtap.
3. Build the `race_match` parity pair (web + both Dart twins) with matched tests.
4. Build `race-results-import` (mirror `parkrun-import`; RunSignUp + paste; fail-closed on missing key) + the `race-listings-sync` stub; Deno tests.
5. Add `data.ts` helpers (search, submit, import, find-match-candidates).
6. Build `/races` discovery page (reuse `SocialDiscover` patterns) + cards/editor; Playwright.
7. Wire the RunSignUp card in Settings → Integrations; wire run-detail official-result render + "Find my result".
8. Implement the auto-match-on-record seam: post-save layered-resilience-wrapped candidate check → non-blocking inform-tier prompt → confirm → enrich the run row (web run-detail first, then mobile).
9. Mirror calendar + auto-match prompt + RunSignUp tile to mobile (both twins, byte-identical); widget tests with the `tester.runAsync` gotchas.
10. Add all i18n keys (every web locale + seven ARBs).
11. Docs sweep (roadmap #10, parity, integrations, metadata.md writer flip, api_database, decisions ADR, CLAUDE.md parity entry, e2e dev accounts).
12. Run `/check` before each commit; keep RunSignUp fail-closed (no key in CI/dev).

## Runners' photos on the race page (shipped 2026-10-15)

Issue #1150 item 4, [decisions § 1961](../architecture/decisions.md). The public `/share/race/[id]` page shows a **Runners' photos** grid, hidden when empty. A photo is on it only when all of these hold, checked at read time by `race_listing_photos(p_listing_id, p_limit default 24, capped at 60)`:

- its owner ticked **Show on race page** on that photo (`run_photos.race_gallery`, written only through `set_run_photo_race_gallery`; never at upload, never on a run-less host photo);
- its run is public and `runs.race_listing_id` is this listing;
- `thumb_512_path` is set, so the `photo_process` worker has stripped EXIF;
- it is not hidden, the owner's profile is not shadow-hidden, and viewer and uploader have not blocked each other.

The page gets the thumbnail, caption, time and the uploader's display name, never a run id, owner id or track. The gallery loads in the browser, not in the share-entity Lambda, so none of it reaches the page head or a link unfurl. Making the run private or unlinking the race removes the photo immediately; the owner can untick it at any time. The toggle lives on the owner's run photos on web `/runs/[id]` and on mobile run detail; it is shown only when the run has a race link, and enabling is disabled on a private run. Tests: `apps/backend/supabase/tests/race_listing_photos_test.sql`, `apps/web/tests-e2e/races/race-listing-photos.spec.ts`, `apps/mobile_android/test/run_photos_race_gallery_test.dart`, `packages/api_client/test/race_listing_photos_rpc_test.dart`.

## Race detail page (shipped 2026-10-17)

[decisions § 2082](../architecture/decisions.md). A calendar card opens a signed-in detail page from anywhere on it but its own action buttons (web: the race name's link is stretched over the card; mobile: one `InkWell` over the card, read as one button by a screen reader): web `/races/[id]` (`routes/races/[id]/+page.svelte`, client-rendered), mobile `RaceDetailScreen` (`screens/race_detail_screen.dart`, both twins). It reads the listing through the redacted `public_race_listings` view (`fetchRaceListing` on both platforms; a malformed id or a missing row is not-found, a failed read is an error with retry) and shows the race's date, distance and place, who lists it ("Listed on RunSignUp", or "Added by a runner" for a `manual` listing), then **Train for this race** (same `racePlanPreset` gate as the card), **Race page & register** (`entry_url`), **View results** (`results_url`), **Share** (the public `/share/race/{id}` link, built by `buildRaceShareCanonical` / `raceShareUrl`) and **Import my result**. Below that, **Your runs at this race** lists the runner's own runs whose `race_listing_id` is this listing (`fetchMyRunsAtRace`, newest first, with the imported chip time), and on web the opted-in runners' photos from `race_listing_photos`. The phone has no photo reader yet; its run rows are not tappable, because the run detail screen needs a full run object, not an id.

**The filters sit behind one control** ([decisions § 2155](../architecture/decisions.md)). The calendar's top band is a single row: the name search, and a **Filters** button with a count of active filters. Near a place (with Use my location on web), Upcoming | Recent results and the distance bands open from it. On web (`/races`) that is an inline disclosure (`races-filters-panel`) and every control's hint is inside it. On mobile (`RacesScreen`) it is a modal bottom sheet, and each change applies at once. An active filter also shows above the list as a removable chip, in one horizontally scrolling row. Filter state is in memory only on both platforms, and the web URL carries none of it.

**The import is offered from race day on**, on the card and the detail page alike (`race_date <= today` in the viewer's calendar). Before race day the detail page says when it opens instead. **Upcoming | Recent results** at the top of the calendar (web `/races`, mobile `RacesScreen`) switches between races from today on and the last 30 days newest first (`RECENT_WINDOW_DAYS` / `recentWindowDays`), so a race the runner has run is still one tap from its import; the newest-first order is `search_race_listings`' `p_newest_first`, because the server caps the set ([decisions § 2083](../architecture/decisions.md)). The run's own auto-match prompt remains the other way in.

**"Register" reads "Race page & register"**, because for a RunSignUp listing `entry_url` is the race's own page on RunSignUp, which carries the course and details as well as registration. RunSignUp's separate `external_race_url` was measured on the first armed sweep and left unstored: 2 of 10 dated Utah races carried one, and one of the two was a charity's home page rather than the race's.

The import dialog is one component on web, `RaceImportDialog.svelte`, used by both `/races` and `/races/[id]`; its per-leg credential probe is the shared `race_import_probe.svelte.ts`, which asks each leg once per session (a probe spends the import function's own rate limit, and a 429 reads as unavailable). Tests: `apps/web/tests-e2e/races/race-detail.spec.ts`, `apps/mobile_android/test/race_detail_screen_test.dart`, and the race-day gate in `races_screen_test.dart`.

