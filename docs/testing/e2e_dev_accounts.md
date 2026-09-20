# E2E test coverage + dev accounts needed

Quick reference for "what's covered by Playwright today" and "what needs a real dev account before we can e2e it". Pair with [local_testing_stubs.md](local_testing_stubs.md) which covers *manual* testing of these flows.

## Covered today — no dev account needed

All of the following run in CI against the local Supabase stack. The seed user (`runner@test.com` / `testtest`) is the canonical actor.

### Web — auth + legal

| Surface | Spec file | What's pinned |
|---|---|---|
| Landing | `landing/page.spec.ts` | Page renders, footer present |
| Sign in (email + password) | `auth/login.spec.ts` | Rejects bad creds, happy-path resets password |
| Sign up | `auth/login.spec.ts` + `auth/signup-age-gate.spec.ts` + `auth/signup-confirmation-pending.spec.ts` | 16+ + ToS gating, happy-path signup ends on /dashboard, and the confirmation-pending outcome drops back to the sign-in form (identically for an already-registered address) |
| Password reset via Mailpit | `auth/reset.spec.ts` | Recovery email → reset → new password → re-sign-in |
| /privacy, /terms, /cookie-notice | `legal/pages.spec.ts` | Pages render with draft banner |
| Cookie consent banner | `cross-cutting/cookie-consent.spec.ts` | Show / hide / persist / Sentry gate |
| Pro pricing currency | `settings/pricing-localization.spec.ts` | $ / £ / € per locale |

### Web — core product

| Surface | Spec file | Notes |
|---|---|---|
| Dashboard | `dashboard/page.spec.ts`, `dashboard/period.spec.ts`, `cross-cutting/dashboard-journey.spec.ts` | Weekly mileage, PBs, goal cards |
| Runs (list / detail / new / photos / social / save-as-route) | `runs/*.spec.ts` | Full coverage of the run lifecycle |
| Routes (list / detail / import) | `routes/*.spec.ts` | Including GPX import |
| Plans (list / create / detail / workout-detail) | `plans/*.spec.ts` | Wizard + week grid |
| Clubs (list / detail / posts / events / members / approval / invite / join) | `clubs/*.spec.ts` | Full social-layer suite |
| Feed | `social/feed.spec.ts`, `cross-cutting/feed-journey.spec.ts` | Activity feed with author filter |
| Settings (account / devices / export / integrations / licenses / preferences / privacy-zones / upgrade / restore-backup) | `settings/*.spec.ts` | Almost every tab |
| Share (run / route public pages) | `share/*.spec.ts` | Anon read-through |
| Profile | `u/profile.spec.ts`, `u/notifications.spec.ts` | Follow toggle + notifications inbox |
| Explore (public routes) | `explore/page.spec.ts` | Search + filters |
| Live spectator (UI only) | `live/spectator.spec.ts`, `live/event.spec.ts` | Simulated pings |
| Coach (with mocked SSE) | `coach/page.spec.ts` | Chat surface mounts; 429 path + happy-path mocked |
| Compare | `compare/page.spec.ts` | Strava-comparison table |
| Guided runs | `guided/page.spec.ts` | Library + detail |
| Recap | `recap/page.spec.ts` | Year-in-running surface |
| Sitemap | `sitemap/page.spec.ts` | XML + robots.txt |

### Cross-cutting

- `cross-cutting/auth-walls.spec.ts` — every protected route redirects to /login when anon.
- `cross-cutting/paywall-wire.spec.ts` — Pro-only API endpoints reject when subscription_tier=free.
- `cross-cutting/realtime.spec.ts` — Supabase Realtime subscriptions deliver.
- `cross-cutting/sign-in-out.spec.ts` — full sign-in → /dashboard → sign-out → /login.
- `cross-cutting/db-constraints.spec.ts` — CHECK constraints fire on bad inserts.
- `cross-cutting/privacy-zones.spec.ts` — non-owner viewers see clipped tracks.
- `cross-user/{kudos, comments, follows, notifications, sagas}.spec.ts` — multi-user behaviours.

### Backend (not Playwright, but covered)

- `apps/backend/supabase/functions/**/*.test.ts` — ~210 Deno tests across ~15 files on shared helpers + webhook/checkout/export handlers.
- `apps/backend/supabase/tests/*.sql` — pgtap suite for RLS / SECURITY DEFINER / triggers.
- `apps/job_worker/internal/**/*_test.go` — Go tests for the worker, live-hub, dataexport, premium endpoints.

## Blocked — need a dev account to fully e2e-test

If you want to wire any of the below up, here's exactly what to create. Until then we either use a mock (per-spec `page.route()` stub like `coach.spec.ts` does), exercise the local-Supabase happy path only, or document the gap.

### 1. Google Sign-In — Google Cloud OAuth credentials

**What's needed:**
- Google Cloud project → Credentials → OAuth client → **Web application**.
- Authorized JavaScript origin: `https://your-domain.com` (+ `http://localhost:7777` for local).
- Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback` (prod), `http://localhost:54321/auth/v1/callback` (local).
- Paste the Web client id into Supabase Dashboard → Authentication → Providers → Google → Authorized Client IDs.

**What you can test once configured:**
- E2E: button click → real Google account picker → return to /dashboard.
- Stub mode (today): we can test the button renders + click handler is wired, but not the post-Google return.

**Already covered by the mock-OIDC lane (`e2e-web-sso`, 2026-06-10):** the entire OAuth path *downstream of the provider redirect* — `signInWithOAuth` → GoTrue authorize → callback `?code` → `exchangeCodeForSession` → real Supabase session → the `/auth/confirm-age` age/terms gate → the app — is exercised end-to-end against a local `oauth2-mock-server`. GoTrue special-cases `google`/`apple` (validates them against the real providers), so the mock stands in as the generic `keycloak` provider; the **only** un-exercised piece is the provider *identity* (a literal Google account picker). See `apps/web/tests-e2e/sso/README.md`. A real Google dev account is therefore needed **only** for that final identity check, not for the callback/session/age-gate code.

**Test strategy when wired (real provider-identity check):**
A dedicated `e2e-test@gmail.com` test account. The actual id-token validation happens server-side at Supabase, so a fully-mocked *Google* flow doesn't work — you need the real account OR a sandbox token from Google's auth-emulator (limited support). This is a manual / non-CI check, since the post-redirect behaviour is already covered by the mock lane above.

### 2. Apple Sign-In — Apple Developer account

**Provisioning lives in [`docs/ops/apple_provisioning.md`](../ops/apple_provisioning.md)** — the living runbook, with a status ledger, for every artifact the Apple membership feeds (APNs, Sign in with Apple, distribution). It is not restated here, because the two copies drifted the moment one was edited: this section used to say the `.p8` contents go into Supabase's Apple provider, and they do not — Apple's client secret is a JWT signed *with* the key, capped at six months, which is a recurring obligation a "what's needed" list has nowhere to put.

**Status today:** the Developer Program is active (2026-09-19); the Apple-side identifiers are outstanding. The web code is done and fail-closed — `/login`'s Apple button runs `startOAuthSignIn('apple')` behind `PUBLIC_APPLE_AUTH_ENABLED`, sharing Google's handler so the 16+/ToS gates and the `/auth/callback` consent stash apply identically. Unset, which is the default everywhere including `.env.development`, the button keeps its label behind a "Soon" pill.

**What a dev account buys you here: the Apple identity step, and nothing else.** Everything downstream of the provider redirect — `signInWithOAuth` → GoTrue authorize → callback `?code` → `exchangeCodeForSession` → session → the age/terms gate — is already exercised by the mock-OIDC lane (`e2e-web-sso`, see § 1). GoTrue special-cases `apple` exactly as it does `google`, so the mock stands in as `keycloak`. The un-exercised piece is the Apple account picker itself.

**So this stays a manual, non-CI check**, and it cannot become anything else: Apple refuses an `http://` return URL, so no local stack can hold a Services ID that points at it. `apps/web/src/lib/core/oauth_provider_gates.test.ts` is the compensating guard — it reads the login page's source and fails if either provider stops picking its handler off its own flag, or if the consent gate stops preceding the redirect.

### 3. Strava — Strava API application + test account

**What's needed:**
- <https://developers.strava.com> → Create an App.
- Client ID + Client Secret.
- Authorization Callback Domain: `localhost` for local, your domain for prod.
- `STRAVA_CLIENT_ID` + `STRAVA_CLIENT_SECRET` in `apps/backend/.env.local`.
- `STRAVA_ALLOWED_REDIRECTS` (your exact callback URLs).

**What you can test once configured:**
- E2E: web settings → Connect Strava → real OAuth dance → activities sync.
- Today: ZIP-import path runs against fixture files in `fixtures/strava/` (test-only). The OAuth + webhook paths exist but aren't e2e-tested.

**Test strategy when wired:**
Two Strava accounts (one as the "user", one as a "buddy" to exercise the privacy filter); spec drives the OAuth handshake with the user's real session.

### 4. Garmin Connect — developer-program approval (BLOCKED)

**Status:** Per `docs/product/roadmap.md`, Garmin Connect Developer API requires application + manual approval that's currently outstanding. Until that lands no Garmin e2e is possible.

**Workaround today:** the Garmin ZIP-import path (single .fit OR Account-Data .zip) IS wired and could be e2e'd with a fixture file. Track in roadmap.

### 5. Stripe + RevenueCat — sandbox accounts (free)

**What's needed:**
- Stripe dashboard → switch to **Test mode**. Grab `pk_test_…` and `sk_test_…`.
- RevenueCat → new sandbox project; paste Stripe `sk_test_…` into Integrations → Stripe. Create the `pro_monthly` product mapped to a Stripe test-mode price.
- `PUBLIC_REVENUECAT_WEB_CHECKOUT_URL` (RC sandbox Web Paywall Link `https://pay.rev.cat/<token>`) in `apps/web/.env.local`; optional `PUBLIC_REVENUECAT_WEB_PORTAL_URL` for the manage-subscription link.
- `REVENUECAT_WEBHOOK_SECRET` (RC webhook signing secret) in `apps/backend/.env.local`.
- Optional but recommended: install `stripe` CLI for `stripe listen --forward-to http://127.0.0.1:54321/functions/v1/revenuecat-webhook`.

**What you can test once configured:**
- E2E: /settings/upgrade → "Get Pro" → Stripe test card 4242 4242 4242 4242 → returns to app → webhook flips tier → `auth.isPro` becomes true.
- Today: the upgrade page renders, button click would fail with "Pro checkout is not configured on this build" (the `isRevenueCatConfigured()` fallback). Pricing display is e2e-tested at the unit level.

**Test strategy when wired:**
`pricing-localization.spec.ts` already covers locale. Add a `purchase-flow.spec.ts` that uses Stripe's published test cards + listens to RC webhook delivery via the CLI shim. Pinning the tier-flip via a `webhook_events` row insert is the canonical assertion.

### 6. Apple In-App Purchase / Google Play Billing — device-only

**Status:** Cannot be e2e-tested on a laptop. Both flows require a real iOS / Android device with a sandbox-tester account signed into the App Store / Play Store. See [local_testing_stubs.md § Apple IAP / Google Play Billing](local_testing_stubs.md#apple-iap--google-play-billing) for manual setup.

**What you can test today:** the in-app purchase button on mobile renders; the rest is integration test on device.

### 7. Anthropic API — for the AI Coach

**What's needed:**
- <https://console.anthropic.com> → API keys → create a key (`sk-ant-…`).
- `ANTHROPIC_API_KEY` in `apps/web/.env.local` for local dev, or the Lambda env in prod.

**Status today:** `coach.spec.ts` mocks the SSE response via `page.route('**/api/coach', ...)`. Real Anthropic calls cost ~$0.01/chat at typical context — fine for occasional manual testing, but the mocked path is the canonical e2e signal.

**Alternative — free local stub:** `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://localhost:11434/v1` + `OPENAI_MODEL=llama3` points the Coach handler at a local Ollama instance. Zero cost, slower responses.

### 8. Sentry — for the error monitoring + replay

**Status today:** every tier is wired and fail-closed; the DSN is the only missing
piece, and it is a **prod-only** concern. Every gate carries `!dev`, so Sentry
cannot fire in local dev or in CI no matter what is set — there is nothing to put
in `apps/web/.env.local` and nothing to e2e. `check_production_env.mjs` deliberately
does **not** require the DSN (an unset value disables reporting rather than
breaking a build), so nothing fails while this is open. Tracking: #922 § 6.

#### 8a. Sign up — the region choice is irreversible

Do this once, deliberately. Sentry's data region is picked in the **Create a New
Organization** dropdown at signup and, for SaaS orgs, *"once selected, your data
storage location can't be changed. The only way to switch it is by creating a new
organization."*

**Choose EU (Frankfurt, `de.sentry.io`), not the US default.** This project forwards
error envelopes carrying EU end-user context to Sentry as a sub-processor; a May 2026
`/audit/cookie-consent` finding (recorded in the `hooks.server.ts` header comment) was
precisely that EU IPs reached a US sub-processor with no lawful basis. Picking US here
re-creates that problem at the storage layer, where no amount of client-side gating can
undo it, and hands `docs/compliance/sub-processors.md` a transfer that needs SCCs.

1. <https://sentry.io/signup/> — free **Developer** plan: 5k errors/month, 1 user,
   **unlimited projects**, 30-day retention. Two projects therefore cost nothing.
2. One form carries all of it — Name, Organization, Email, Password, Data Storage
   Location. Fill it as:
   - **Name** — the account holder's real name; it shows on issue activity.
   - **Organization** — `Threkir` (slug `threkir`).
   - **Email** — a role alias on the domain, **`ops@threkir.com`**, forwarding to the
     owner's real inbox. Create the alias in Migadu *before* signing up; Sentry sends a
     verification mail straight away. Not a personal mailbox: the free plan is
     single-seat, so this login *is* the org, with no second admin to recover through —
     a lost personal mailbox would take production monitoring with it, and a vendor
     account rooted in one doesn't transfer with the domain. `ops@` rather than
     `sentry@` so the next vendor (Better Stack, Fly, Supabase) can share it. Same
     pattern as the existing `dmarc@threkir.com`.
   - **Password** — generated into the password manager.
   - Leave the email-updates checkbox unticked; it is marketing, not alerting.
3. **Use email + password, not the Google / GitHub / Azure buttons.** They bind the org's
   login to a personal identity account and buy nothing here — the Sentry↔GitHub
   integration that links issues to commits is a separate org-level install under
   Settings → Integrations either way.
4. **Data region: Europe (Frankfurt).** Verify afterwards that the browser lands on
   `de.sentry.io` — if it says `us.sentry.io`, delete the org and redo this step.
5. A 14-day Business trial starts automatically. Let it lapse; it downgrades to
   Developer on its own. Do not add a card.

An EU-region DSN reads `https://<key>@o<org>.ingest.de.sentry.io/<project>`. The
`.de.` is correct, not a typo — a DSN with `.us.` means step 3 was missed.

#### 8b. Create exactly two projects

The repo has two DSN slots, so it gets two projects. Names and platforms are not
cosmetic — the platform drives issue grouping and the setup docs Sentry shows.

| Project name | Platform to pick | Feeds env var | SDKs reporting into it |
|---|---|---|---|
| `threkir-client` | **SvelteKit** (under the JS frameworks list, not plain Browser JavaScript — the web SDK is `@sentry/sveltekit`) | `PUBLIC_SENTRY_DSN` | `@sentry/sveltekit` (browser half), `sentry_flutter`, `io.sentry:sentry-android` (Wear OS), `sentry-cocoa` (watchOS, SwiftPM package not yet added — needs a Mac, #922 § 8) |
| `threkir-backend` | **Deno** | `SENTRY_DSN` | `deno.land/x/sentry` (Edge Functions), `@sentry/sveltekit` (SSR/prerender half), coach Lambda |

Both projects are multi-SDK — `threkir-client` also takes Flutter and Wear OS events —
so the platform field only sets the project's primary hint and which setup docs Sentry
shows; each event carries its own platform tag. Unlike the region, it is changeable
afterwards under Settings → Projects → `<project>` → General.

Ignore the install walkthrough Sentry shows after creating each project. Every SDK is
already wired; the DSN on that page is the only thing needed from it. Grab each at
**Settings → Projects → `<project>` → Client Keys (DSN)**
(`/organizations/threkir/settings/projects/<project>/keys/`).

The DSN hostname is also the only trustworthy region check once an org exists: an EU org
ingests at `o<id>.ingest.de.sentry.io`, a US one at `...ingest.us.sentry.io`. The org URL
is `<slug>.sentry.io` in both regions, so it proves nothing, and Sentry offers **only**
these two regions — a settings field reading anything else (a UK billing country, say) is
not the data-storage location.

**A DSN is not a secret** — Sentry: *"DSNs are safe to keep public because they only
allow submission of new events and related event data; they do not allow read access."*
The client one already ships inside the browser bundle. They live in secret stores below
only because that is where each build reads them from, not because they need protecting.
Don't burn a rotation drill on one leaking.

#### 8c. Put the DSNs where each tier reads them

Four destinations. The client DSN goes to one, the backend DSN to two.

- **Client DSN → GitHub repo secret.** Repo-level, matching its `PUBLIC_*` siblings
  (`PUBLIC_MAPTILER_KEY`, `PUBLIC_SUPABASE_URL`) — *not* the `production` environment,
  which holds the signing keys. `release-web.yml` bakes it into `.env.production` and
  `release-android.yml` re-reads the same secret into `--dart-define=SENTRY_DSN`, so one
  secret covers web and both mobile twins:
  `gh secret set PUBLIC_SENTRY_DSN --repo Absence0760/threkir`
- **Backend DSN → Supabase Edge Function secrets**, which every EF reads through
  `withSentry()`:
  `cd apps/backend && supabase secrets set SENTRY_DSN="<paste>" APP_RELEASE="backend@$(git describe --tags --abbrev=0)"`
- **Backend DSN → sops**, for the coach Lambda and the SvelteKit server half. Every key
  in the env's sops file is merged into the coach Lambda env:
  `bin/secret-set.sh prod SENTRY_DSN --prompt`
  then `(cd ../infra-secrets && git add threkir/prod.sops.yaml && git commit -m 'threkir: sentry dsn')`
- **Apply, then repoint the alias.** An env-only apply publishes a new Lambda version but
  leaves the CI-owned `live` alias on the old one (issue #590), so the rotation does not
  actually serve until the second command runs:
  `bin/deploy-prod.sh && bin/lambda-alias-sync.sh prod`

Repeat the last two for `preview` if that env should report too. Wear OS takes
`SENTRY_DSN` as a Gradle property; watchOS reads it from `Info.plist`.

#### 8d. Settings to change before real traffic

The free plan's 5k errors/month is shared across both projects, and a single hot loop in
one EF can exhaust it in an afternoon — at which point *everything* stops reporting,
silently, including the failure you needed to see.

1. **Settings → Security & Privacy → Data Scrubbing** (org-level; the same section
   exists per-project under Settings → Projects → `<project>` → Security & Privacy).
   Scrubbing is on by default — leave it on, and additionally enable the control that
   prevents IP addresses from being stored. The code already scrubs (`sentry_scrub.ts`,
   `$lib/sentry/redact`, `sendDefaultPii: false`, and `beforeSend` dropping
   `request`/`user`/`server_name`), but that is sender-side; a server-side rule is the one
   an auditor can verify independently of our build.
2. **Know which failure the plan gives you.** On Developer there is no bill to cap —
   over-quota events are *dropped*, so the risk is silent blindness, not spend. Set a
   spend cap only if this is ever upgraded to Team, where pay-as-you-go overage becomes
   billable; that cap would be the Sentry twin of the Anthropic console ceiling in
   #922 § 2, since no code can enforce a provider-side limit.
3. **Per-project → Settings → Client Keys**: leave rate limits off initially, then set a
   per-key cap once a normal-traffic baseline exists.
4. Both projects → **Alerts**: the default "high volume" rule is noise for a 1-user org.
   One rule per project — *a new issue is created* → email — is enough to start.

#### 8e. How to know it worked

`release` ties an event to a build (`web@1.6.0` from `PUBLIC_APP_RELEASE`,
`backend@<tag>` from `APP_RELEASE`), so a first event with `release: dev` means the
release wiring is wrong even though the DSN is right.

- **Web:** load <https://threkir.com>, **accept the cookie banner** — the client gate is
  `!dev && dsn && hasAcceptedConsent()`, so a declined banner correctly reports nothing —
  then check `threkir-client` for the session.
- **Backend:** call any deployed EF with a deliberately malformed body and confirm an
  event lands in `threkir-backend` tagged with that EF's name.
- **Still empty?** In order: the build predates the secret (re-run the release; each re-run
  needs **Approve and deploy** clicked again, `docs/ops/releasing.md:85`); the `live` alias was never
  repointed (`bin/lambda-alias-sync.sh prod`); or consent was declined.

**Not covered by any of this:** `apps/job_worker` and `apps/graph_cycle` carry no Sentry
SDK at all — no `sentry-go` in either `go.mod`. A worker panic is invisible to Sentry
after every step above is done, and the worker is what drains the digest and lifecycle
mail. `apps/job_worker/deployment.md` § Monitoring routes that signal through pg_cron
summary functions and a log scraper instead. Wiring `sentry-go` into both is open code
work, not a credential blocker.

### 9. MapTiler — for map tiles

**What's needed:** Free at <https://maptiler.com/cloud>.
- `PUBLIC_MAPTILER_KEY` in `apps/web/.env.local`.

**Status today:** Maps render in dev. The free tier covers all local testing. E2E tests that exercise the map (`runs/detail.spec.ts`, `routes/detail.spec.ts`) work as long as the key is set.

### 10. FCM (Android) + APNs (iOS) push notifications

**What's needed:**
- A Firebase project with a `com.threkir.app` app on each platform — the two config files become repo secrets, not committed files.
- An FCM service account (Android sends) — the config files do not sign anything.
- Apple Developer Program + an APNs auth key (iOS sends, direct to APNs; not uploaded to Firebase).
- A VAPID pair for browser push, whose public half has to match in two systems.

Nothing here is Supabase Auth configuration — push is a consumer of the `notifications` table drained by the Go worker. The ordered runbook is [`native_push.md` § Operator provisioning](../features/native_push.md#operator-provisioning-the-credential-gate).

**Status today:** `device_tokens` table rows write correctly (covered by spec); actual delivery is gated on real upstream credentials. Today there's no automated push-delivery test.

### 11. parkrun — no sandbox available

**Status today:** parkrun is a public scraper, no API/sandbox. The `parkrun-import` Edge Function takes an athlete number; testing requires a real athlete number that's run real events. Use your own number for manual testing.

**Test strategy:** mock the upstream fetch in the Edge Function via dependency injection (the function is already structured for this; `apps/backend/CLAUDE.md` § Testing without real credentials documents the pattern).

### 12. RunSignUp API key — for live race-results import

**What's needed:** a RunSignUp REST API key + secret (`RUNSIGNUP_API_KEY` / `RUNSIGNUP_API_SECRET`), set as Edge-Function secrets on the deployed Supabase project (and in `apps/backend/.env.local` for local manual testing). Apply at <https://runsignup.com> → partner/API access.

**Status today:** the race-calendar + results-import feature is **shipped fail-closed** (migration `20270214_001`, race_calendar.md). With the key unset — the dev/CI default — `race-results-import` + `race-listings-sync` return `503 provider_not_configured` and the UI shows the unavailable explainer. The e2e suite covers exactly this gated state: `races/runsignup-gate.spec.ts` asserts the Settings card shows the explainer (no crash), and `races/race-calendar-discover.spec.ts` + `races/race-result-import-manual.spec.ts` cover the calendar discovery + **manual paste** import + auto-match-on-record paths, which need no RunSignUp key. The live RunSignUp pull is the only un-e2e'd leg; provisioning the key is a deploy-time checklist item, not a code blocker.

### 12b. ChronoTrack Live (CTLive) credentials — for live race-results import

**What's needed:** a ChronoTrack Live API account — `CHRONOTRACK_CLIENT_ID` + `CHRONOTRACK_USER_ID` + `CHRONOTRACK_PASSWORD` (all three required together), set as Edge-Function secrets on the deployed Supabase project (and in `apps/backend/.env.local` for local manual testing). Apply via ChronoTrack / CTLive partner/API access.

**Status today:** the ChronoTrack leg is **shipped fail-closed** (2026-06-20) on the same `race-results-import` EF behind the `provider:'chronotrack'` branch. With the credentials unset — the dev/CI default — the import branch + the `probe:true` availability check return `503 provider_not_configured` and the Settings ChronoTrack card shows the unavailable explainer. `races/chronotrack-gate.spec.ts` asserts that gated state; the Deno `lib.test.ts` covers the CTLive mapping + the fail-closed `chronoTrackConfigured` gate. The live CTLive pull is the only un-e2e'd leg; provisioning the three credentials is a deploy-time checklist item, not a code blocker.

## Summary — what to create first

If your goal is "get the e2e suite to cover everything", the **best ROI** is:

1. **Stripe + RevenueCat sandbox** — frees up the entire paywall flow (about a day of e2e wiring).
2. **Google Cloud OAuth credentials** — Google Sign-In, ~15 min to configure.
3. **Anthropic API key** — Coach real-mode if you ever want to verify the model response shape against fresh Anthropic releases.

If your goal is "ship to international" without further e2e investment, the **existing coverage is already strong** — the gaps are:
- Real OAuth flows (mocked or skipped, both are defensible).
- Real payment flows (sandbox-tested manually before each release; sufficient for a $9.99/month consumer SaaS).
- Mobile e2e (separate doc — [docs/testing/mobile_e2e.md](mobile_e2e.md)).
