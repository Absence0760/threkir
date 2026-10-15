# Sharing a run or a route without making it public

Status: **built on web, backend and mobile (Android + iOS twin), behind a default-OFF server gate.** Prod stays closed until the CISO / Security Analyst review below. Decisions § 1874 to § 1879. Migrations `20270802000001` (gate + followers level), `20270802000002` (grant tables), `20270802000003` (visibility).

## What the owner gets

A run or a route the owner can see sits at one of four levels, chosen in **Who can see this**:

| Level | Stored as | Who can open it |
|---|---|---|
| **Only me** | `is_public = false`, `followers_only = false`, no grant | the owner |
| **Followers** | `followers_only = true` | the owner's followers (the people who follow them) |
| **Specific people** | owner-only columns plus rows in `run_shares` / `route_shares` | the people the owner named |
| **Public** | `is_public = true` | anyone with the link; appears in feeds and search |

- **Named people** are picked from the owner's follow graph, either direction (people they follow and people who follow them), never a stranger, and never across a block. The rail enforces it (`private.can_share_with`), not only the picker.
- **Revocable at any time.** A revoke deletes the grant; access is checked on every read, so it ends on the recipient's next request. Choosing Only me revokes every grant first (with a confirm when any are live). The wider levels leave grants in place: they come back into force if the owner narrows again.
- **Clipped.** Every non-owner sees the track and the route polyline with the owner's privacy zones trimmed (decisions § 33 unchanged): runs through `clip-public-track`, routes through `clip_route_for_viewer`.
- **Never broadcast.** Feeds, `run_completed` notifications (§ 96), profile lists, the sitemap, heatmap, challenges and the `public_runs` / `public_routes` views all key on `is_public`, which neither narrower level touches. A shared run is opened from a link, not discovered.

What follows the entity automatically, because each already asks `private.is_run_visible_to` / `is_route_visible_to`: kudos, comments, photos (§ 98's coach exclusion stays), run gear, live pings (already zone-dropped at insert), route markers, conditions, reviews, segment efforts and leaderboards, and DM route attachments. A follower who reads a followers-level run can therefore kudo and comment on it, and their own leaderboard view includes the owner's effort on it.

## Surfaces

- **Web (canonical).** `AudienceDialog.svelte` on run detail and route detail. **Share** on a non-public entity opens it rather than offering only a public flip; Public goes through the existing privacy-zone confirm. At Followers or Specific people, Share copies the in-app link (`/runs/{id}`, `/routes/{id}`), which opens only for that audience. Sending a private route to a follower by DM grants that one person access instead of making the route public ([route_direct_share.md § Private send](route_direct_share.md#private-send)). A recipient sees a "Shared with you" marker.
- **Mobile.** `widgets/audience_sheet.dart`, opened from Share on run detail and from **Share link** on route detail. Same four levels, the same people rail, revoke per person, and **Share link** at the narrower levels hands the in-app web link to the OS share sheet. **Recipient view:** a run or route shared with the viewer opens in the existing non-owner screens, `public_run_screen.dart` and `public_route_screen.dart`, which read public first and then `shared_runs` / `shared_routes` for a signed-in caller (`ApiClient.fetchViewableRunById`, the `shared_routes` fallback in `fetchRouteById`), take the track from `clip-public-track` / `clip_route_for_viewer` only, carry no owner control, and show the same **Shared with you** marker as web (`widgets/shared_with_you_chip.dart`). The entry point is the one web has, the link: `lib/entity_link.dart` opens `https://threkir.com/runs/{id}` / `/routes/{id}` (an Android App Link, UUID ids only) and `com.threkir.app://runs|routes/{id}` (both platforms) in the app, the runner's own run or route on its owner screen and anything else on the non-owner one (decisions § 1882). There is no shared-with-me list and no notification, on either client, because a share is never broadcast.
- **Not changed.** `/share/run/{id}` and `/share/route/{id}` and the `share-run` / `share-route` Lambdas read the public views only, so a share link to a non-public entity is not-found for a signed-out viewer and in social unfurls.

## Privacy default

The `privacy_default` value `followers` used to mean private, because a run had only `is_public`. It now writes `followers_only` on every creation path (web save + importers, the phone's run save, the `parkrun-import` / `strava-import` Edge Functions, the Go worker's Strava ingest) — see [settings.md § privacy_default detail](../backend/settings.md#privacy_default-detail). An account that never chose a default falls back to `private`, not `followers` (decisions § 1881), so opening the gate widens nothing nobody chose. While the gate is closed the server stores it private, so a run saved before sign-off does not widen on the day the gate opens.

## The gate (decisions § 150)

`private.feature_flags` row `audience_sharing`. No migration writes it; `seed.sql` opens it for local stacks and CI. With it closed:

- the audience oracles answer false, so every helper, view and clip reads exactly as before the feature;
- the grant INSERT policy refuses every new grant;
- `normalize_audience()` stores `followers_only` false;
- `audience_sharing_enabled()` returns false and both clients hide the control and keep the old public / private behaviour.

### Pre-deploy checklist

- [ ] **CISO / Security Analyst review** of the audience oracles, the `shared_*` projections, and the `clip-public-track` branch, before `insert into private.feature_flags (name, enabled) values ('audience_sharing', true)` runs in prod. Recorded in [deployment.md](../ops/deployment.md).

## Private profiles (decisions § 1967)

The account-level complement to the per-run levels above, and **not** behind the `audience_sharing` gate: `user_profiles.profile_private` defaults false, so nothing changes for anyone until they turn it on (Settings → Privacy on web, the Privacy group of Preferences on mobile). Migrations `20270822000001` + `20270822000002`.

- **What closes.** A private profile's public runs, gym sessions and food entries, their photos, kudos and comments, its follower and following lists, and its share page (`/share/profile/{id}` is not-found, so nothing unfurls) open only to the owner and to **approved followers**. A segment or challenge leaderboard keeps the effort but drops the name for a viewer outside that set.
- **What stays.** Name, avatar and handle, so the profile can be found and asked; the follower and following **counts**; routes, event results, recaps and badges, each published individually; a run's live safety link while the broadcast is in progress (the runner sent it to be watched); a run shared with named people or followers (those audiences are the owner's own choice).
- **Requests.** Follow on a private profile becomes **Request to follow**, then **Requested** (tap again to withdraw). The owner gets a `follow_request` notification (inbox, plus email and push under the default `important` channel mode, muted on its own by `notify_follow_request`; decisions § 1983) and approves or declines on `/follow-requests` (web) or the Follow requests screen (mobile, from Settings or the notification). Turning the switch off approves every pending request. A block clears a request either way.
- **No prod gate.** Default-off is the gate; there is no sign-off item. Shipping it does change behaviour for one population: an old phone build that inserts into `user_follows` directly gets a refusal on a private target and shows its generic follow error.
- **Tests.** pgtap `private_profiles_test.sql`; web unit `notification_link.test.ts` / `notification_groups.test.ts`; Playwright `tests-e2e/social/private-profile.spec.ts`; mobile `follow_requests_screen_test.dart`, the private cases in `profile_screen_test.dart` and `people_screen_test.dart`.

## Known limits

- **`routes.run_count` drift.** The count's authoritative query asks whether each runner can see the route, which a follow, a grant or the gate can now change without touching a run row. It is the same accepted, self-healing drift [derived_state.md](../backend/derived_state.md#routesrun_count) already records for a route's own visibility flip.
- **Wear OS and the watch apps** write runs without the privacy default (owner-only); unchanged.

## Tests

- pgtap `apps/backend/supabase/tests/audience_sharing_test.sql` — the visibility matrix (owner / named recipient / revoked recipient / follower / stranger / anon × owner-only / followers / shared / public, runs and routes), grant RLS, clipped routes, feeds + notifications excluded, block and shadow-hide, and the closed gate.
- Deno `clip-public-track/viewable_run.test.ts` + `wiring.test.ts`; `export-data/backup_spec.test.ts`; `_shared/privacy_default.test.ts`; Go `supabase_privacy_default_test.go`.
- Web unit `social/run_visibility.test.ts`; Playwright `tests-e2e/runs/audience-sharing.spec.ts` and the Share step in every spec that makes a run or route public (`fixtures/share.ts`).
- Mobile `test/audience_level_test.dart` (parity pair with `run_visibility.ts`), `test/audience_sheet_test.dart`, `test/shared_recipient_view_test.dart` (recipient run + route: clipped track only, no owner control, marked shared, nothing with the gate closed), `test/entity_link_test.dart` + the link group in `home_screen_test.dart`, the audience cases in `run_detail_screen_test.dart` / `route_detail_screen_test.dart`, `preferences_test.dart`; api_client `run_upsert_and_live_pings_test.dart` (a re-sync never clears the followers level) and `shared_entity_read_test.dart` (public first, the shared view for a signed-in caller only, never the base table, the route clipped).
