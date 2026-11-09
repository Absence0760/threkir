# Deployment overview

Where every service runs in production, who owns it, what it costs, and how it gets there.

This is the **plan**, not a record of what's already deployed. Most services are still local-only at the time of writing — the per-service docs spell out what's shipped vs. what's a forward-looking proposal. Update each section the moment something flips from "plan" to "live".

For the orthogonal "how a tag triggers a build" mechanics, see [releasing.md](releasing.md). For the strategic phase-by-phase architecture story, see [backend_scaling.md](../backend/backend_scaling.md). This file is the ops-side counterpart: where the bytes physically run.

---

## What runs where

| Service | Path | Provider | Status |
|---|---|---|---|
| Web app (static + Coach SSR) | `apps/web/` | **AWS** — S3 + CloudFront + Lambda Function URL + Route 53 (Terraform-provisioned, sops + AWS KMS for runtime secrets, OIDC-deployed) — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) | **Live** — threkir.com serves from CloudFront (verified 2026-07-20) |
| Backend (Postgres + Auth + Storage + Edge Functions) | `apps/backend/` | **Supabase Cloud** | **Live** — project `mcbgrgvegqcmdmtraikl`, East US (Ohio) |
| Job worker (Go) | `apps/job_worker/` | **Fly.io** (`threkir-worker`, region `ord`) — single machine, distroless; sited next to the Ohio Supabase project, not next to the team | **Live** — deployed 2026-07-21, queue draining + live hub serving (auth JWKS-verified, smoke matrix passed); client cutover pending (`PUBLIC_LIVE_HUB_URL` / `LIVE_HUB_URL` unset, so recorders/spectators still ride Supabase Realtime) |
| OSRM (map-matching engine) | `apps/job_worker/osrm/` | **Fly.io** (`osrm`, region `lhr`) — single machine + Volume | Plan |
| GraphHopper (`round_trip` route generator, `foot` profile) | `apps/job_worker/graphhopper/` | **Fly.io** (`graphhopper`, region `lhr`) — serves the "Generate a route by distance" loop endpoint; reached by the generate-route Lambda over public https with an `X-Engine-Key` Caddy guard | Plan |
| graph_cycle (v3 loop generator map sidecar) | `apps/graph_cycle/` | **Fly.io** (`graph-cycle`, region `lhr`) — distroless Go service, parses an OSM PBF into an in-memory foot graph; in-process `X-Engine-Key` guard | Plan |
| Coach LLM | `apps/web/src/routes/api/coach/+server.ts` (deployed as a Node 24 Lambda) | Anthropic Claude (default) — `OPENAI_BASE_URL` for self-host | Plan (web) |
| Mobile Android | `apps/mobile_android/` | **Google Play** — Internal → Beta → Production tracks | Plan |
| Mobile iOS | `apps/mobile_ios/` | **App Store Connect** — TestFlight → App Store | Plan |
| Wear OS | `apps/watch_wear/` | **Google Play** — separate listing (`com.threkir.watchwear`) | Plan |
| Apple Watch | `apps/watch_ios/` | Bundled inside the iOS app — no separate listing | Plan |
| RevenueCat | (third party) | RevenueCat dashboard — webhook to `apps/backend/supabase/functions/revenuecat-webhook` | Plan |
| MapTiler | (third party) | MapTiler Cloud — `PUBLIC_MAPTILER_KEY` shared by web + Wear OS | Plan |
| Anthropic API | (third party) | api.anthropic.com — `ANTHROPIC_API_KEY` reaches the coach Lambda as part of a KMS ciphertext the handler decrypts at cold start, never as a plaintext env var (Terraform reads it from the sops file in the private estate repo and encrypts it under the env's own CMK — [decisions § 1671](../architecture/decisions.md)) | Plan |

Per-service deep dives:

- [`apps/backend/deployment.md`](../../apps/backend/deployment.md)
- [`apps/web/deployment.md`](../../apps/web/deployment.md)
- [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) (covers the OSRM stack too)
- [`apps/mobile_android/deployment.md`](../../apps/mobile_android/deployment.md)
- [`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md) (covers Apple Watch bundling)
- [`apps/watch_wear/deployment.md`](../../apps/watch_wear/deployment.md)

Cross-service operator runbooks:

- [`apple_provisioning.md`](apple_provisioning.md) — every artifact the Apple Developer membership feeds (APNs, Sign in with Apple, distribution), in the only order that works, with a status ledger that is ticked as each step lands.
- [`google_provisioning.md`](google_provisioning.md) — the Google Cloud side of Google sign-in: the consent screen Google renamed to Google Auth Platform, the three OAuth clients, the Supabase provider and the two build-time gates. Same ledger shape; shares only the Supabase pages with its Apple sibling.

---

## Topology

```
                          users
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
      threkir.com                  app stores
      ─────────────                  ──────────
      Route 53 → CloudFront          Play Store (Android)
        ├── default → S3 (static)    Play Store (Wear OS)
        └── /api/coach/* → Lambda    App Store (iOS + watchOS)
            │
            ├────► api.anthropic.com (or self-hosted via OPENAI_BASE_URL)
            │
            └────► Supabase Cloud (<ref>.supabase.co)
                   ├── Postgres + PostGIS
                   ├── Auth (email + Google + Apple)
                   ├── Storage (runs/, route-files/, run-photos/)
                   ├── Realtime
                   ├── Edge Functions (parkrun-import, refresh-tokens,
                   │                   strava-import, strava-webhook,
                   │                   revenuecat-webhook, delete-account,
                   │                   export-data)
                   └── pg_cron (mv refresh, rate-limit GC, ping cleanup)
                          ▲
                          │ service-role REST + Storage
                          │
                          ▼
                   Fly.io private network (6PN)
                   ├── job_worker  (1+ machines, shared-cpu-1x)
                   │     └─ drains kind='map_match' jobs
                   │     └─ drains future kinds (strava-webhook,
                   │        token-refresh, data-export per
                   │        backend_scaling.md)
                   └── osrm  (single machine, performance-2x, 8 GB)
                         └─ /match/v1/foot — talks only on 6PN,
                            no public route

                   third-party webhooks
                   ├── RevenueCat → revenuecat-webhook EF (HMAC)
                   └── Strava → strava-webhook EF (shared ?secret=)
```

---

## Domain and DNS

Buy `threkir.com` (or whatever the brand ends up as) at one registrar. Recommended: Cloudflare Registrar (no markup, free DNSSEC) or Porkbun.

Subdomain map:

| Subdomain | Points at | TTL |
|---|---|---|
| `threkir.com` | Route 53 ALIAS → CloudFront distribution | 300 |
| `www.threkir.com` | Route 53 ALIAS → CloudFront distribution | 300 |
| `api.threkir.com` | Reserved for the Supabase custom domain (Pro + add-on) — **not provisioned on the current Free tier**; clients use the raw `<ref>.supabase.co` | 300 |
| `live.threkir.com` | CNAME → `threkir-worker.fly.dev` — the Go live spectator hub (TLS at Fly's edge via `flyctl certs add`) | 300 |
| `worker.threkir.com` | Not exposed publicly — internal Fly.io 6PN address only | — |
| `osrm.threkir.com` | Same — never publicly resolvable | — |

The Coach endpoint lives under `threkir.com/api/coach`; CloudFront routes that path to a Lambda Function URL while everything else hits the S3 origin. Same domain, same CORS posture as the static site — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages).

**Email-from domain** (for transactional email — password resets, magic links): `noreply@threkir.com` via SendGrid or Resend. Configure SPF + DKIM + DMARC at the same DNS provider. Supabase's default `noreply@mail.app.supabase.io` works in dev but ends up in spam folders for half the population in prod.

---

## Cost ladder

Numbers are USD/month at the launch tier (1000 active users, ~5 runs/user/month). Update as we scale.

| Service | Tier | Monthly |
|---|---|---|
| AWS — S3 + CloudFront + Lambda + Route 53 | Free tier covers Lambda + most CF egress for year one; Route 53 hosted zone $0.50; S3 storage <$0.50; CF egress past free tier ~$0.085/GB | $1.50 → ~$5 |
| Supabase | Pro ($25) — required for daily backups, custom domain, larger compute | $25 |
| Fly.io — job_worker | shared-cpu-1x, 256 MB | $5 |
| Fly.io — OSRM | performance-2x, 8 GB RAM, 20 GB Volume | $30 |
| Fly.io — bandwidth | mostly internal 6PN (free); Storage egress goes through Supabase | <$5 |
| MapTiler Cloud | Free tier (100k tile reqs/mo) covers development, testing and a closed pre-launch only (MapTiler Support, 2026-11-06); a public commercial launch needs a paid plan, which is also what makes a countersigned DPA available | $0 pre-launch → paid plan at launch |
| Anthropic API | Coach usage at ~$0.003 per chat turn × ~5k turns/mo | $15 |
| Domain | Cloudflare Registrar (.app cost) | ~$1.5 |
| Email (Resend) | Free tier 3k emails/mo → $20 above | $0 → $20 |
| Apple Developer Program | $99/year ÷ 12 | $8.25 |
| Google Play Console | $25 once (not recurring) | $0 |
| RevenueCat | Free up to $2.5k/mo MTR → 1% above | $0 → variable |

**Launch baseline: ~$70/month.** Scaling drivers (CloudFront egress past 1 TB once the free year ends, OSRM RAM as we add regions, Anthropic at higher coach usage) push that toward $200–300 in the 10k-user range. Detailed projections per service in each `deployment.md`.

**Cost-minimized launch:** to ship for a few dollars a month, [`deployment_lean.md`](deployment_lean.md) records which services to defer (the two Fly routing engines, the worker, mobile stores, coach) and why each degrades gracefully — a **Lean** tier (~$34–49/mo, Supabase Pro + worker, backups intact) and a **Rock-bottom** tier (~$3–4/mo, Supabase Free + web-only). Every deferral re-attaches later by setting one env var or standing up one Fly app.

**Cost-control ceilings (what stops a runaway):**

Each spend vector carries at least two independent caps — one in IaC, one (where possible) in the provider console:

- **AWS account total** — `aws_budgets_budget` in [`infra/envs/prod/budgets.tf`](../../infra/envs/prod/budgets.tf) fires at 50 % / 100 % ACTUAL and 100 % FORECASTED of `monthly_budget_limit_usd` (default $200). The FORECASTED notification is the one that catches a runaway *during* the month — ACTUAL lags by up to 24 h.
- **Lambda concurrency** — `lambda_reserved_concurrency` in [`infra/envs/{prod,preview}/main.tf`](../../infra/envs/prod/main.tf) caps per-env concurrency (prod 20, preview 5). Throttle alarms cover coach, generate-route and osrm-proxy; prod fires on the first throttled invocation (`lambda_throttle_alarm_threshold = 1`), preview at 5. Subscribed via `alert_emails` (validated non-empty + placeholder-rejected on both envs).
- **CloudFront edge cost** — `price_class = PriceClass_100` in [`infra/modules/web-stack/main.tf`](../../infra/modules/web-stack/main.tf) bills only NA + EU edge locations (skips SA + AU which 10× the per-GB cost). WAF `aws_wafv2_web_acl` rate-limits `/api/coach*` at 100 req / 5 min / IP via the scope-down filter — keeps static-asset traffic outside the rate-limit envelope.
- **CloudWatch log retention** — every log group sets `retention_in_days` ≤ 90 (default "Never expire" is $0.50/GB/month forever).
- **S3 lifecycle** — non-current versions expire at 30 d, incomplete multipart uploads abort at 7 d (prevents version-history cost ramp).
- **Coach per-user cap** — `TIER_LIMITS.free.dailyLimit` in [`apps/web/src/lib/coach/types.ts`](../../apps/web/src/lib/coach/types.ts) caps free at 2 messages/UTC-day, server-enforced before any Anthropic call. Pro is daily-uncapped but each turn is capped at `maxTokens = 2048`.
- **Anthropic console spend limit** — **MUST be set manually** at https://console.anthropic.com/settings/limits — code cannot enforce a provider-side ceiling on a key that's leaked from a sops file. The recommended floor is ~2× the projected monthly Anthropic spend (~$30/mo at launch baseline, so $60–$100 cap). **Set by hand 2026-09-18.** Nothing in this repo can confirm that — re-verifying it means opening the console, so treat the date as the record.
- **Supabase egress alert** — **MUST be set manually** in Supabase project settings. Code cannot enforce a daily-egress ceiling at the provider level.

The full audit + arch-guard tests covering each ceiling live in [`apps/web/src/lib/infra_guards.test.ts`](../../apps/web/src/lib/infra_guards.test.ts) under the "audit:cost-controls" section.

---

## Observability

The bar for v1 is: **someone gets paged when the site is down, can read the relevant logs, and can roll back without thinking.** Anything beyond that is nice-to-have.

| Surface | Tool | What we get | Cost |
|---|---|---|---|
| Web (AWS) | CloudWatch Logs (Lambda) + CloudWatch Metrics + CloudWatch alarms | request volume, 4xx/5xx rate, cache hit ratio, Lambda p95 + cold-start rate | <$1/mo |
| Backend (Supabase) | Supabase Dashboard → Logs | Postgres slow queries, EF invocations, Auth events | included |
| Worker + OSRM (Fly.io) | `fly logs -a threkir-worker` / `fly logs -a osrm` + native metrics | per-machine CPU/RAM, restart history, log stream | included |
| Cross-service errors | **Sentry** — single org, separate projects per service | grouped exceptions, release tagging, breadcrumb trail on mobile | $0 (free tier) → $26 (team) |
| Uptime | **Better Stack** or **UptimeRobot** | external probe of `/`, `<ref>.supabase.co/rest/v1/…`, `threkir.com/api/coach` (HEAD-only — expect **405 + `Allow: POST`**, not a 2xx: the coach Lambda is POST-only since [decisions § 896](../architecture/decisions.md), and before that a HEAD answered 401. Either status is proof the function is alive; configure the monitor on the status, not on 2xx) | $0 (free tier) |
| RevenueCat / Stripe events | dashboards on each | subscription lifecycle, churn signals | included |

**Alerts that page someone** (Better Stack → email + push):

1. `threkir.com/` returns non-200 for >2 min
2. `<ref>.supabase.co/rest/v1/runs?select=count` returns non-200 for >2 min (proxy for "PostgREST is up + DB reachable + RLS still permits reads")
3. Worker hasn't claimed a job in >10 min while `jobs.status='queued'` count > 0 (worker stuck)
4. OSRM `/health` non-200 for >5 min
5. Sentry: any new error class with >10 events in 5 min

Not paging on:
- Single failed Edge Function call (transient, EF logs catch the trend)
- Single client-side JS error (Sentry rolls up; investigate on a schedule)
- Worker `defer_job` calls (those are the *correct* response to a transient)

### Synthetic checks on an API path assert `content-type`, not status

The distribution maps `403 -> 200 /200.html` for **every** origin at once —
`CustomErrorResponses` is a member of `DistributionConfig` and `CacheBehavior`
has no error-response member at all, so the API behaviours cannot opt out of it
([CloudFront API reference](https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_CacheBehavior.html),
confirmed 2026-09-18). The mapping is load-bearing — every SPA deep link is a
missing S3 key, i.e. a 403 — and its cost is that **a refusal from any origin
reaches the caller as `200 text/html`**. No status-code check can tell that from
a working endpoint, which is how a malformed request read as a production outage
in September 2026 and produced a merged fix for a bug that did not exist (#938,
reverted by #941; [decisions § 1664](../architecture/decisions.md)).

`bin/preview-status.sh <env>` step 2 runs
[`scripts/probe_api_content_type.mjs`](../../scripts/probe_api_content_type.mjs),
which derives every `/api/*` cache behaviour from
`infra/modules/web-stack/main.tf` and asserts that each answers
`application/json` on both GET and POST. Every API Lambda in this tree answers
`application/json` for its refusals too, so an unauthenticated request is a
complete test. Run it against any deployed host on its own:

```bash
node scripts/probe_api_content_type.mjs --host threkir.com
node scripts/probe_api_content_type.mjs --derive   # offline; what CI runs
```

Two things follow for anyone adding an external monitor or debugging by hand:

- **An HTML body on an `/api/*` path is a masked 403, not a broken handler.**
  Check both CloudFront invoke grants on the function (`lambda:InvokeFunctionUrl`
  **and** `lambda:InvokeFunction`, issue #590) before looking at the code — a
  Function-URL refusal happens above the function, so there is no invocation,
  no `Errors` metric and no log line to find.
- **A POST through CloudFront must carry `x-amz-content-sha256`.** CloudFront
  signs the origin request with sigv4 and "Lambda doesn't support unsigned
  payloads"
  ([OAC for Lambda function URLs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-lambda.html)),
  so a POST without the viewer-supplied payload hash is refused at the origin
  and served as the shell. It is the caller's header, not something an origin
  request policy can add — #938 tried that and CloudFront refuses it.

---

## Backups and disaster recovery

| What | How | RTO | RPO |
|---|---|---|---|
| Postgres | **Free tier today: no automated backups** — periodic manual `pg_dump` until the Pro upgrade (Pro: daily backups, 7-day window; PITR closes the gap to ~5 min) | 30 min | last manual dump (Pro: 24 h → ~5 min with PITR) |
| Storage (`runs`, `route-files`, `run-photos`) | Supabase Storage built-in (object versioning is opt-in per bucket — turn it on for `runs`, leave off for `run-photos` to save cost) | 2 h | 24 h |
| OSRM graph | Reproducible — `make download && make build` against a Geofabrik PBF; ~15 min on the build machine. We do **not** back up the extracted graph. | 15 min | N/A (regenerable) |
| Worker state | Stateless — every claim is a fresh DB read. Restart loses nothing. | seconds | 0 |
| Mobile / watch local stores | User's device + Supabase row mirror. The local store is a cache, not a source of truth. | N/A | N/A |
| Web deployment artifact | Static build zip attached to each `web@*` GitHub Release; coach Lambda versions retained by AWS for rollback via the `live` alias. Redeploy by re-running the workflow against an older tag. | 5 min | per-deploy |

**RTO** = recovery time objective (how long to get back up). **RPO** = recovery point objective (max acceptable data loss).

Run a full restore drill **once per quarter**. The procedure (in [`apps/backend/deployment.md`](../../apps/backend/deployment.md) § Disaster recovery): take a fresh Supabase project, restore the latest backup into it, point a staging build at it, verify a smoke run. Without a drill, the backup is a fiction.

---

## Secrets management

Never commit a production secret. Three storage layers, in order of preference:

1. **Provider-native secret store** — Supabase Vault (already set up for OAuth tokens via `get_integration_tokens` / `set_integration_tokens` per [decisions.md § 41](../architecture/decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns)), AWS Secrets Manager (the coach Lambda's `ANTHROPIC_API_KEY` and server-side `SENTRY_DSN`), Fly.io secrets, GitHub Actions secrets. Scoped to the service that needs them.
2. **`.env.local` files** — gitignored, present on developer laptops and CI runners that need them. Templates committed as `.env.example`.
3. **The private estate secrets repo** (`Absence0760/infra-secrets`, sops + per-project AWS KMS — see the repo-root CLAUDE.md § Production secrets) — durable source of truth for long-lived key material that must survive a lost workstation (e.g. the Android upload keystore at `threkir/android-upload-keystore.sops.yaml`). Access is IAM (`kms:Decrypt`); Bitwarden holds the owner's interactive credentials. There is no 1Password anywhere in this estate.

The matrix of "what lives where":

| Secret | Origin | Stored in |
|---|---|---|
| `SUPABASE_SECRET_KEY` (`sb_secret_…`; legacy `service_role` JWT also accepted) | Supabase project settings | Fly.io secrets (worker) |
| `SUPABASE_ANON_KEY` (publishable) | Supabase | GitHub Secrets (injected into web build at CI build-time as `PUBLIC_SUPABASE_ANON_KEY`); Mobile build configs |
| `STRAVA_CLIENT_SECRET` | Strava developer dashboard | Supabase Vault |
| `STRAVA_VERIFY_TOKEN`, `STRAVA_WEBHOOK_SECRET` | We invent | Supabase EF env |
| `REVENUECAT_WEBHOOK_SECRET` | RevenueCat dashboard | Supabase EF env |
| `ANTHROPIC_API_KEY` | Anthropic console | sops-encrypted in the private estate repo (AWS KMS key per env) — Terraform decrypts at apply time, RE-encrypts it into `aws_kms_ciphertext.coach`, and writes only that blob to the coach Lambda's `environment` block; the handler decrypts it once per cold start ([decisions § 1671](../architecture/decisions.md)) |
| `PUBLIC_MAPTILER_KEY` | MapTiler dashboard | GitHub Secrets (injected at CI build-time as `PUBLIC_*`); Mobile build configs |
| Android upload keystore | We generate once | GitHub Secrets (`ANDROID_KEYSTORE_BASE64`) |
| iOS distribution `.p12` + provisioning profile | Apple Developer | GitHub Secrets (`IOS_BUILD_CERTIFICATE_BASE64` etc.) |
| Wear OS upload keystore | We generate once | GitHub Secrets (`WATCH_WEAR_KEYSTORE_BASE64`) |
| Play `service-account.json` | Google Cloud | GitHub Secrets (`PLAY_SERVICE_ACCOUNT_JSON`) |
| App Store Connect `.p8` API key | Apple Developer | GitHub `production` environment secret `APP_STORE_CONNECT_API_PRIVATE_KEY` (the raw `.p8` text); backed up in the estate |
| Sign-in-with-Apple `.p8` + the OAuth client secret it signs | Apple Developer | The `.p8` in the estate (`siwa_key_p8`), the Supabase EF env (`APPLE_PRIVATE_KEY`, for revocation) and the GitHub `apple-secret-rotation` environment (`APPLE_SIWA_PRIVATE_KEY`). The derived ES256 JWT lives only in the Supabase Apple provider; `rotate-apple-client-secret.yml` re-signs it on the 1st of every month, because Apple refuses one older than six months ([`apple_provisioning.md` § 9](apple_provisioning.md), [decisions § 1824](../architecture/decisions.md)) |

**Scheduled rotation**: the Apple OAuth client secret is the one credential that expires on a fixed clock without a leak, so it is the one rotated by a workflow rather than by hand. That workflow runs on a reviewer-less `apple-secret-rotation` environment restricted to `main`, not on `production`, because a cron run that waits for an approval rotates nothing; a red run opens an `apple-secret` issue.

**Rotation rule**: if a secret is suspected leaked, the rotation is in three steps: (1) issue a new key in the provider, (2) update everywhere it's stored, (3) revoke the old key. Step 3 is what "the old one is dead" really means — without it the leaked key still works.

### Owed: move `STRAVA_WEBHOOK_SECRET` off the query string, then rotate it

**Status: open. Do this before the Strava webhook path is considered production-hardened.**

The Strava callback is registered as `https://<host>/…?secret=<STRAVA_WEBHOOK_SECRET>`, because Strava's subscription API accepts a callback **URL** and nothing else — there is no place to configure a header. A query-string secret is written verbatim into the receiver's request log on **every** delivery (Supabase function logs for the Edge Function, the worker's HTTP log for the Go endpoint), so anyone with log read access recovers it and can forge activity ingests into any user's `runs` by enumerable Strava athlete id.

Both receivers now also accept the secret from an `X-Webhook-Secret` header, preferred over the query param and compared in constant time on both paths (`apps/backend/supabase/functions/strava-webhook/index.ts`, `apps/job_worker/internal/stravahook/server.go`). That is the half that is code. The rest is operator work and must run **in this order**:

1. Confirm both receivers are deployed with header support (the Go worker is the production path; the Edge Function is the rollback path — **both**, or a rollback re-opens the hole).
2. Mint a new `STRAVA_WEBHOOK_SECRET` (≥ 32 chars — both receivers refuse below that floor).
3. Set the new value on the worker (Fly.io secret) and the Edge Function env, and **re-register the Strava subscription** with a callback URL that still carries `?secret=` set to the new value. Strava cannot send the header, so the query path stays live for Strava itself; the point of the rotation is that the value in the logs is no longer the one anything else trusts.
4. Revoke the old value — it is in every historical log line and must be treated as public from here on.
5. Any non-Strava caller of these endpoints (replay tooling, smoke tests, the manual recipes in [manual_testing.md](../testing/manual_testing.md)) switches to the header.

Until step 4 lands, treat the secret as compromised-if-logs-are: the channel is authenticated but not confidential. Recorded in [decisions.md § 567](../architecture/decisions.md).

**Operator scripts.** The AWS-side rotation flows are wrapped in [`bin/`](../../bin/README.md): `secret-set.sh <env> <KEY>` (rewrite a single sops-encrypted Lambda secret without opening an editor), `key-rotate.sh <env>` (re-encrypt under a new KMS key when the key itself is replaced), and `onboard-operator.sh <arn>` (grant a second human/role decrypt access on the env's KMS key). All take input via stdin / file / prompt — nothing routes secrets through argv or shell history.

**Lambda env rotations need an alias repoint.** An env-only `terraform apply` publishes a new Lambda version but the eight web Lambdas' `live` aliases are CI-owned and stay behind, still serving the previous version's frozen env — the rotated secret isn't live until the alias moves (issue #590 defect 2). `bin/deploy-preview.sh` / `bin/deploy-prod.sh` repoint them automatically after every apply of `infra/envs/<env>`, holding any alias that was already behind before the apply (a possible rollback) with a warning, and exit non-zero naming the manual command if the repoint fails ([decisions § 1825](../architecture/decisions.md)). An apply made any other way — a bare `terraform apply` — still needs `bin/lambda-alias-sync.sh <env>` afterwards (or a `web@*` release, whose deploy repoints the aliases anyway).

---

## Merge gates — what protects `main`, and the one scanner that does not

Every deploy starts with a merge, so the merge gate is the first production
control. Branch protection on `main` requires **exactly one status context**:
`CI gate`, the aggregator job in `.github/workflows/ci.yml`. It waits on the
other 40 jobs in that file and fails if any of them reports anything but
success or skipped.

`build-mobile-ios` joined the required set on 2026-09-20. It compiles
`apps/mobile_ios` for the iOS simulator (`flutter build ios --simulator
--no-codesign`, so no signing credential and no Apple Developer account are
needed) and runs the `RunnerTests` XCTest bundle. It is the only lane that
compiles the Flutter iOS target at all, and its XCTest step is the only place
in CI that launches the iOS binary -- `RunnerTests` is hosted by `Runner.app`,
so `AppDelegate` and `GeneratedPluginRegistrant` run for real and a plugin
whose iOS registration crashes at launch is caught. It is also the one
required job that does NOT take the broad `code` path filter. The cost is not
money -- this repo is public, so standard GitHub-hosted runners are free,
macOS included -- but ~15-20 min of wall clock against one of a small number
of concurrent hosted macOS runners, so it is gated on the `changes` job's `mobile_ios`
output and skips on a web-only, backend-only, firmware-only or docs-only PR.
A skip is a pass at the gate, so a green `CI gate` on such a PR means the iOS
target was not compiled -- which is correct, because nothing in that diff can
reach it.

Most of that build's plugin graph is fetched through Swift Package Manager
(~27 git repositories plus prebuilt binary zips from `dl.google.com`), so the
job caches the remote-derived halves of `apps/mobile_ios/build/ios/SourcePackages`
-- the `-clonedSourcePackagesDirPath` Flutter passes to xcodebuild -- keyed on
`Package.resolved`, and the `RunnerTests` step reuses that directory instead
of resolving the graph a second time into DerivedData. Before that, one
dropped download failed the lane on a PR that touched no iOS code (run
37947299387). A fetch failure that still gets through is reported as a Swift
package download failure, not as "does not compile". After the build, the job
fails if Xcode rewrote either committed `Package.resolved`: a pubspec bump that
moves a plugin's exact Swift package requirement must land with regenerated
pins, or the build runs on pins nobody committed and the cache stays keyed on
the stale ones (run 42412145141, where that re-resolution crashed xcodebuild).

A `needs:` entry is scoped to its own workflow, so a job in a sibling workflow
file can never be waited on directly. Two workflows reach the gate anyway by
being **called instead of triggered** -- `terraform.yml` ([decisions
§ 1149](../architecture/decisions.md)) and `gitleaks.yml` ([§
1264](../architecture/decisions.md)) are `on: workflow_call`, and `ci.yml` has
a one-line job for each. A called workflow's job results fan into the calling
job, so one `needs:` entry covers every job those files hold today and every
one they gain later.

**`gitleaks.yml` is called AND scheduled, and only the called half gates.** The
`workflow_call` path diffs against the base ref; the weekly `cron` is the only
scan that reads the whole of `main`'s history, and it reaches the gate by no
route at all -- it runs on no PR. It failed every week from 2026-05-18 to
2026-09-21 without that being visible anywhere ([decisions
§ 1697](../architecture/decisions.md)). `gitleaks-sweep.yml` now holds that cron, calls the same
scan, and opens a `secret-scan`-labelled issue on a failed sweep, closing it on
the next clean one -- the shape `audit.yml` already uses. It is a separate file
because a callee may not request a permission its caller lacks, and putting the
`issues: write` in `gitleaks.yml` failed `ci.yml` at startup. The issue carries the run link and never the
findings, because this repository is public. A red weekly sweep is therefore an
open issue rather than a merge block -- deliberately, since the history it
reads is already merged and blocking the next unrelated PR would not unmerge
it.

### What runs on a pull request and does not block it

Seven workflows trigger on a pull request and reach nothing the gate waits for.
Each is a decision rather than a backlog item, and the decisions live in code:
`PR_ADVISORY` in
[`scripts/check_ci_diagnostics.mjs`](../../scripts/check_ci_diagnostics.mjs)
holds one entry each with the reason folding it into `ci.yml` would be the
**wrong** answer rather than the unmade one, and that guard's rule 7 fails the
PR when a pull-request-triggered workflow is in neither the gate nor the
register. Rule 8 compares the list below against the register in both
directions, so this section cannot quietly drift out of step with the code the
way a hand-maintained duplicate does -- a name here that the register has
dropped, or an entry there this list never mentions, fails `workflow-lint`.

- `security.yml` -- CodeQL's `analyze` declares no severity threshold, so a
  fold would gate on the analysis completing rather than on what it found. The
  section below is entirely about this one.
- `pr-title-lint.yml` -- it triggers on `edited`, which is how a corrected
  title re-lints. `ci.yml` carries no `types:` and deliberately not that one,
  since `edited` rebuilds every job on a description typo.
- `compliance-drift.yml` -- advisory by construction: it runs in warn mode and
  asks a human whether a doc applies to the diff, which is a judgement rather
  than a verdict.
- `labeler.yml` -- it labels a pull request and asserts nothing about it, so
  there is no verdict for a gate to wait on.
- `dependabot-auto-merge.yml` -- it ACTS on a pull request (approve + enable
  auto-merge) rather than checking one, and a required check that merges the PR
  it is required by is a cycle.
- `pr-mergeable.yml` -- it reports when `ci.yml` has **not run at all**, which
  is the state a PR with conflicts is in: no merge ref exists, so no run is
  created, and the two `pull_request_target` checks that do survive read as
  health. Folding it into `ci.yml` would give it `ci.yml`'s fate and silence it
  exactly when it has something to say. Not gating on it is right on its own
  terms too -- `CI gate` is already absent on such a PR, so branch protection
  already blocks the merge; this adds a signal to a reader, not a second lock
  ([§ 1686](../architecture/decisions.md)).
- `supply-chain-scan.yml` -- zizmor (workflow security) and osv-scanner
  (every lockfile) report to code scanning and the job summary and exit clean
  on a finding, so a fold would gate on the scanners completing, which an OSV
  database or GitHub API outage can stop, rather than on what they found.
  Blocking on a finding is a later policy change, after the baseline is fixed
  and the CISO / Security Analyst sign off, made through the code-scanning
  ruleset ([§ 2412](../architecture/decisions.md)).

The register carries each reason in full; the list above is the operator's
index into it. All six go red on a finding and the PR merges anyway, so a red
row from any of them is read rather than waited for. The root `CLAUDE.md` says
the same about `pr-title-lint.yml`'s `lint title` in the words a contributor
meets it in, and rule 8 pins that sentence too.

There is a third option for `lint title` and it is deliberately not taken:
adding it to the required-status-check set is a repo setting, and it is cheap
(the job is ~20 s and depends on nothing). It stays out because the required set
being **exactly one context** is a property worth more than this check --
`ci.yml` is the one place a job's red is guaranteed to block, and every other
guard in this repo has been folded into it rather than added beside it
([§ 1149](../architecture/decisions.md), [§ 1264](../architecture/decisions.md)).
A second context would make "what blocks a merge" a question with two answers,
one of them invisible to every guard in the tree. A bad PR title is caught by a
red row and fixed with a retitle; that is the trade
([§ 1585](../architecture/decisions.md)).


### CodeQL is the exception, and it is a repo setting

`security.yml`'s four CodeQL analyses and two Trivy jobs are **not** in the
gate. Since 2026-10-14 a CodeQL **finding** blocks the merge anyway, through the
repository ruleset **Code scanning gate** on the default branch (id `25104920`):
it requires code scanning results from the `CodeQL` tool and refuses the merge
when the PR introduces a security alert of **high or higher** or any alert at
**error** level; lower-severity notes do not block. Repository admins can
bypass it, which is the escape hatch for a CodeQL outage -- the alternative,
flipping the ruleset to *evaluate*, keeps the record without the lock
([§ 1908](../architecture/decisions.md)). The required status-check set is still
exactly `CI gate`. Before that ruleset, a CodeQL alert did not block a merge,
and the reason why is kept below because it is why the gate is a ruleset and
not a status check. The
call trick above does not fix it, for a reason measured rather than assumed:
`github/codeql-action/analyze` at the pinned SHA declares 18 inputs and not one
of them is a severity threshold (re-read against the action's own `action.yml`
2026-09-06). An alert never turns the job red, so calling `security.yml` from
`ci.yml` would gate on the analysis **completing**, not on what it found -- and
it would re-key every analysis in the Security tab, because the action derives
its analysis key from the *run's* workflow path.

What actually gates a CodeQL finding is a repo setting, and only a repo
setting -- the ruleset above. In **Settings -> Rules -> Rulesets** it is the
**code scanning results** requirement with the `CodeQL` tool at the thresholds
stated there. Leave the required *status check* set at exactly
`CI gate`; do **not** add the four `analyze` job names to it as a substitute,
because that gates on the scan running rather than on what it found. Adding
them is still worth doing if the worry is a scanner that silently stops
working -- a broken extractor or a bad `queries:` value fails those jobs, and
nothing else in CI would notice -- but it is a different guarantee, not a
weaker version of the same one.

Re-derived against the action's own `action.yml` at the pinned SHA on
2026-09-06 rather than inherited from the paragraph above: 18 inputs
(`check_name`, `output`, `upload`, `cleanup-level`, `ram`, `add-snippets`,
`skip-queries`, `threads`, `checkout_path`, `ref`, `sha`, `category`,
`upload-database`, `post-processed-sarif-path`, `wait-for-processing`, `token`,
`matrix`, `expect-error`), and not one is a severity or alert threshold. The
conclusion stands.

**Part of the "scanner silently stops working" worry is now inside the gate,
and it is the part that has actually happened.** Twice a compiled leg reported
clean over source it had never read -- `apps/graph_cycle`
([§ 1304](../architecture/decisions.md)) and 11 Kotlin files under
`apps/mobile_android/android` ([§ 1352](../architecture/decisions.md)) -- because
CodeQL scopes a compiled language to whatever the build steps compile, and a
database holding one tree looks exactly like one holding two. Neither would have
been caught by requiring the `analyze` jobs to pass, because in both cases they
DID pass. `scripts/check_codeql_coverage.mjs` runs in `workflow-lint`, which is
in the gate, and fails the PR when a build step stops covering a tree the repo
holds. What is still outside the gate is a leg that fails outright or a bad
`queries:` value -- loud states, unlike the silent one.

Folding `security.yml` into `ci.yml` the way `terraform.yml` and `gitleaks.yml`
were folded would buy the rest of that second guarantee without a repo setting,
and it has been re-derived and declined three times now, so the cost is recorded
here to stop a fourth: the fold re-keys all four analyses (the action derives
its key from the run's workflow path), and `security.yml`'s own `push` and
`pull_request` triggers would have to be removed at the same time or every merge
runs the analyses twice and two uploads to one SARIF category make the alert set
flip-flop -- the exact failure `security.yml`'s header records being merged to
escape. It is a real option, not a foreclosed one; it is just not free, and it
is not the option that gates a FINDING.

Two things to do at the same time as the setting, because nothing in the repo
can observe it:

- The required set stops being exactly one context. The root `CLAUDE.md`
  ("must pass the single required **CI gate** status check") and this section
  both say it is, and both become wrong the moment the rule is enabled.
- Trivy stays advisory on purpose and is not part of this. Both container jobs
  run at `exit-code: '0'` and report to the Security tab; that is a deliberate
  call recorded in `security.yml`, not an oversight to sweep up here.

Nothing in this repository can read, set, or verify any of the above -- branch
protection is not readable by the workflow token -- so this section is the only
record that the state was ever intended.

**A PR's `security.yml` run is never cancelled once it has started**, so the
ruleset's wait for CodeQL results on a fresh push can include finishing the
analysis already in flight for the previous one (the Kotlin leg is the longest,
~12 minutes). That is deliberate: a CodeQL job killed mid-analysis uploads a
"failed run" SARIF ("unsuccessful execution, exit code: 0"), and the PRs that
cancelled them most were what put "CodeQL is reporting errors" on the Security
tab. A newer push still replaces a run that is only *pending*, which starts no
job and uploads nothing, so a burst of pushes costs one extra analysis, not
one per push. The three Trivy jobs install Trivy through
`.github/actions/setup-trivy` (pinned, checksummed, retried, cached) rather than
trivy-action's own unretried fetch, and upload SARIF only when the scan wrote
one ([§ 2273](../architecture/decisions.md)).

### A merged PR's branch is deleted on merge

**Automatically delete head branches** (`delete_branch_on_merge`) is on as of
2026-09-16. It had been off, and 211 remote branches of merged PRs had piled up
by then. They were deleted the same day, each one pushed with
`--force-with-lease` on the head the PR merged, so nothing pushed after a merge
could go with it.

Two things follow for stacked PRs. Merging a parent **retargets** its open
children onto the parent's base rather than closing them ([GitHub,
2020-05-19](https://github.blog/changelog/2020-05-19-pull-request-retargeting/)).
That retarget is an `edited` event, and no `ci.yml` job runs on `edited`, so a
child whose parent just merged has to be pushed to before it gets a gate run.
The child is also still carrying the parent's commits, not the squash `main`
now holds, so merge `origin/main` into it as the root `CLAUDE.md` describes.

The setting leaves two kinds of branch alone: the branch of a PR that was
closed without merging, and a branch that never had a PR. On 2026-09-16 there
were 16 and 20 of those. They were left for whoever owns them. Like branch
protection, the setting is invisible from inside the tree, so this paragraph is
the only record of it.

### The edge runtime's first-request SIGBUS is fixed by a pinned image

[Issue #916](https://github.com/Absence0760/threkir/issues/916): the local
Supabase stack's edge runtime exited **135 (SIGBUS)** while serving the first
request it got, which is the `start-supabase` action's own readiness probe, so
a job failed before a test ran and reported
`edge runtime (clip-public-track) never became ready`. Seven occurrences
between 2026-09-08 and 2026-09-22, on Playwright shards and on
`Kotlin row codegen drift`. The cause was upstream: the runtime's copy of
Deno's cache layer deleted a cache database another connection still had
mapped ([decisions § 1663](../architecture/decisions.md)). edge-runtime
**v1.77.1** fixed it
([supabase/edge-runtime#746](https://github.com/supabase/edge-runtime/issues/746)),
and `start_stack.sh` pins the runtime to that image through the CLI's own
override file while the CLI itself stays on `2.84.2`
([decisions § 1795](../architecture/decisions.md)).

**Operator action if it recurs:** check the forensics' `image=` line. On
`edge-runtime:v1.77.1` or later it is a new bug, not this one: reopen #916 with
the dump rather than re-running until it passes. On an older image the pin did
not land, which `start_stack.sh` is meant to refuse, so treat that as a bug in
the action.

## Release vs deploy

Two orthogonal axes. **Release** is "we cut a tagged version of the product"; **deploy** is "those bytes are now serving traffic". They overlap in different ways per service. Every `release-*.yml` deploy is **triggered by publishing a GitHub Release** for the tag below (a bare tag push no longer deploys — the published Release is the gate; see [releasing.md](releasing.md)):

| Service | Release tag | Deploy means |
|---|---|---|
| Web | `web@*` | CI builds → `aws s3 sync` to the prod bucket → `aws cloudfront create-invalidation` → `aws lambda update-function-code` for the coach handler. Live within ~60 s of CI success. |
| Backend (migrations + EF) | `backend@*` | Migrations applied + EFs uploaded to the linked Supabase project |
| Job worker | `worker@*` | `release-worker.yml` → `flyctl deploy --remote-only` against the `job_worker` Fly app |
| OSRM | `osrm@*` | `release-osrm.yml` → `flyctl deploy` against the `osrm` Fly app (image only — the graph rides along on the Volume); separate from the worker because it has different rebuild/restart cadences |
| graph_cycle | `graph-cycle@*` | `release-graph-cycle.yml` → `flyctl deploy` against the `graph-cycle` Fly app (the OSM PBF persists on the `graph_cycle_data` Volume; redeploy reparses it on boot) |
| GraphHopper | none | No release workflow yet — still a hand-rolled `flyctl deploy` against the `graphhopper` Fly app from a maintainer's laptop |
| Mobile Android | `mobile_android@*` | `.aab` uploaded to Play Internal track; manual promotion to Beta/Production from the Console |
| Mobile iOS | `mobile_ios@*` | `.ipa` uploaded to TestFlight; manual promotion to App Store from App Store Connect |
| Wear OS | `watch_wear@*` | `.aab` uploaded to Play Internal track for the separate Wear listing |

Tag → workflow → deploy is the canonical path for every Fly service, GraphHopper included — `release-graphhopper.yml` fires on a published `graphhopper@*` release, so no service is left on a hand-rolled `flyctl deploy` from a maintainer's laptop. See [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) § CI wiring.

### Edge Function CORS ships with a backend release, not a web one

The browser-called Edge Functions answer the CORS preflight in their own code (`_shared/cors.ts`, decisions § 2148), so a fix to it — or a new browser-called function — reaches threkir.com only when the functions are redeployed: publish a `backend@<version>` GitHub Release, which runs `release-backend.yml` and redeploys every function (it applies pending migrations too, so check what else is on `main`). A one-off `supabase functions deploy <name> --project-ref <ref>` from `apps/backend/` is the narrower path. Verify with a token-less preflight, which must answer 204 with `access-control-allow-origin: https://threkir.com`:

`curl -s -i -X OPTIONS -H "Origin: https://threkir.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization,content-type" https://<ref>.supabase.co/functions/v1/delete-account`

The allowed origins are `PRODUCTION_ORIGINS` in the helper, not a secret; a new site host (a custom domain, a separate preview project) is a code change there.

### One-off: the SPA-shell cutover from `index.html` to `200.html`

adapter-static's `fallback` moves from `build/index.html` to `build/200.html`
so the prerendered landing page can occupy `build/index.html`. CloudFront's
403 -> shell `custom_error_response` is what serves every deep link (each
dynamic client route is a missing S3 key, so S3 answers 403 and the
distribution substitutes the shell at 200), so the mapping has to follow the
shell to its new name or every deep link serves the landing page instead of
the app.

**Neither single-step order is safe.** Apply the Terraform first and
`/200.html` is a key the bucket does not hold, so a deep link 403s into a
second 403. Deploy the tag first and `/index.html` is the landing page, so a
deep link serves marketing at 200. Both windows last until the other half
lands.

**Three steps, in this order, close both windows** (derived from the workflow
and the Terraform, never executed against AWS -- no lane holds credentials):

1. `aws s3 cp s3://<bucket>/index.html s3://<bucket>/200.html` -- pre-seed the
   CURRENT shell under its new name. The default `--copy-props default` copies
   `content-type` and `cache-control` from the source object, so the copy is
   byte- and header-identical to what a deploy would have written.
2. `terraform apply` the `custom_error_response` change in
   [`infra/envs/<env>`](../../infra/README.md). `/200.html` now resolves to the
   shell deep links were already being served, so nothing about them changes.
3. Publish the `web@*` release. `index.html` becomes the landing page and
   `200.html` the new shell, both in the same `aws s3 sync` pass, and the
   workflow's closing `create-invalidation --paths "/*"` clears any cached
   error-response body rather than waiting out a TTL.

Between 1 and 3 the pre-seeded object cannot be swept: the deploy's first
`aws s3 sync` runs `--delete` but excludes `*.html`, and the CLI's own
reference states that "files excluded by filters are excluded from deletion".
The same two filter rules are why the sync needs no edit for the new file --
pass 2's `--exclude "*" --include "*.html"` matches `200.html` on
last-match-wins, so it uploads with the 60 s HTML cache like any other page.

**The code half is landed; the three steps are all that is left.** When this
section was written the repo was mid-move and the paragraph here warned that
the five share Lambdas still embedded `build/index.html` at bundle time, so
step 3 would bake the landing page into every share handler whatever the
ordering. That is no longer the state. Verified in the tree: `vite.config.ts`
emits `fallback: "200.html"`, all five `apps/web/lambda/share-*/build.mjs`
resolve `build/200.html`, `spa_shell_head_signals.test.ts` reads that artifact,
and the `custom_error_response` in `infra/modules/web-stack/main.tf` names
`/200.html`. `apps/web/src/lib/seo/spa_shell_filename.test.ts` derives the
expected name from the adapter config and fails the PR if any of those rails
drifts back, so the code cannot regress under the operator ([decisions
§ 1272](../architecture/decisions.md)).

**Which environment is this?** The steps are per-distribution and `prod` and
`preview` are cut over independently. To find out whether an environment has
already been through them, read the live mapping rather than assuming:

```
aws cloudfront get-distribution-config --id <DIST_ID> --query 'DistributionConfig.CustomErrorResponses.Items[?ErrorCode==`403`].ResponsePagePath' --output text
```

`/index.html` means the cutover has not happened on that distribution and the
next `web@*` release will break every deep link on it; `/200.html` means steps
1 and 2 are done. `aws s3 ls s3://<bucket>/200.html` answers step 1 on its own.

**The claim that was derived is now measured, on `prod`, 2026-09-10.** It used
to read that none of this had been executed against AWS, because no lane holds
credentials. The step carrying the most weight was that the pre-seeded
`200.html` survives the release's `aws s3 sync --delete`, resting on excluded
keys not being deletion candidates. It does. `prod` was walked through all three
steps in order and `web@1.5.0` published on top: the pre-seed survived the
release, and pass 2 then overwrote it with the new build's shell in the same
run. Deep links were checked after the deploy and came back byte-identical to
`200.html` rather than serving the landing page, which is the failure this
ordering exists to prevent.

Two facts worth carrying forward. `index.html` and `200.html` genuinely diverge
after the cutover -- the landing page measured 15098 bytes against the shell's
5927 -- so the rollback note below is load-bearing rather than theoretical. And
`preview` has not been cut over, because it does not exist: the account holds
one distribution, and `preview.threkir.com` resolves to nothing. The per-
environment framing above still stands for whenever that environment is built.

Rollback is the mirror image: revert the Terraform first (the bucket still
holds an `index.html`, though after a post-cutover deploy it is the landing
page, so re-seed it from `200.html` before reverting), then redeploy the
previous tag.

---

## Pre-flight checklist before going live

Before flipping any service from "Plan" to live in the table at the top:

1. The per-service `deployment.md` is up to date — provider, region, instance size, command to deploy.
2. Secrets are loaded (provider-native + GitHub Actions where the workflow needs them).
3. DNS records resolve from a few networks.
4. An uptime probe is configured.
5. A rollback path is verified — actually run it once against a staging deploy.
6. Update the row at the top of this file from "Plan" to "Live (region)".
7. Tick the corresponding box in [roadmap.md](../product/roadmap.md).
8. If this enables a feature, flip the cell in [parity.md](../product/parity.md).

### Recurring events — move keyed rows onto wall-clock instants (owner-approved)

Migration `20270808000011` (decisions § 1918) changes a timezoned series' occurrences to the organiser's wall-clock and accepts both the old UTC-clock instants and the new ones until the window is closed, so it is safe to push on its own and must be pushed **before** the web release that carries the matching clients. The rows keyed by the old instants do not move on push: the owner runs `apps/backend/scripts/ops/measure_recurrence_wallclock_impact.sql`, approves, and an operator then follows [recurrence_wallclock_remap.md](recurrence_wallclock_remap.md) (dry run, batched remap, web + mobile release, sweeps, close).

### Audience sharing — after the CISO / Security Analyst review

The followers level and named-person run / route shares ([sharing.md](../features/sharing.md), decisions § 1874) ship closed: no migration writes the `audience_sharing` row of `private.feature_flags`, so prod answers exactly as before. Open it only after the CISO / Security Analyst has reviewed the audience oracles, the `shared_runs` / `shared_routes` projections, and the `clip-public-track` branch — then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('audience_sharing', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; every read path falls back at once, and existing grants stay inert until it reopens.

### Challenge invite links — after the CISO / Security Analyst review

Challenge invite links ([challenges.md § Invite links](../features/challenges.md#invite-links-and-the-public-share-page-2026-11-03-decisions--2261), decisions § 2261) ship closed: no migration writes the `challenge_invite_links` row of `private.feature_flags`, so the invite card and the join-by-link page stay dark and a non-public challenge stays joinable only as before. Open it only after the CISO / Security Analyst has reviewed migration `20271103000001` (the private token table, the anon-callable `challenge_invite_preview` projection, the `join_challenge_by_token` rate limit) and both clients' join surfaces — then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('challenge_invite_links', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; every token stops resolving at once and no participant is removed. The public `/share/challenge` page is not behind it.

### Streamer overlay and live heart rate — after the CISO / Security Analyst review

The streamer overlay ([flows.md § Streamer overlay](../features/flows.md#streamer-overlay), decisions § 2265) ships closed: no migration writes the `live_overlay` row of `private.feature_flags`, so the Settings card, the phone's "Streamer overlay" entry and `/live/overlay` stay dark, and every live ping is stored and relayed **without** its `bpm`. Open it only after the CISO / Security Analyst has reviewed broadcasting live location and heart rate to an audience: migration `20271104000001` (the private `live_overlay_tokens` table, the anon-callable `live_overlay_feed` and its server-side delay, the `live_run_pings_strip_bpm_before_insert` trigger, the service-role-only `live_heart_rate_shared`), the Go hub's bpm strip (`apps/job_worker/internal/livehub/server.go`), and heart rate on `/live/[id]` and the phone's spectator screen. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('live_overlay', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`: every overlay token stops resolving at once and new pings lose their `bpm` again. The hub caches the consent answer per room for `CacheRefreshTTL`, so a hub room already open keeps its answer until the next refresh.

### Share-link attribution — after the CISO / Security Analyst review

Share-link visit counters, sign-up attribution and Your shares ([decisions § 2268](../architecture/decisions.md), migration `20271104000004`) ship closed: no migration writes the `share_attribution` row of `private.feature_flags`, so no link carries a ref, no visit is counted, no sign-up records `signup_share`, and Your shares is hidden on both clients. In order:

1. CISO / Security Analyst: confirm the aggregate counter (`private.share_link_daily`, written by the anon-callable `record_share_visit` from the share page; no cookie, IP, user agent, user id or browser storage) needs no cookie consent, and review the bounded write path (public entities only, capped daily counters, 90-day purge).
2. CISO / Security Analyst: decide whether sign-up attribution (`signup_share` in the GoTrue metadata, counted by the `auth.users` trigger) is a new purpose, and if so update [dpia.md](../compliance/dpia.md) and have counsel add its row to the privacy policy's § 3 purpose table. [sub-processors.md](../compliance/sub-processors.md) does not change: no vendor is involved.
3. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('share_attribution', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; counting and attribution stop at once, and the existing buckets age out under `purge-share-link-daily`.

### First-touch sign-up source — after the CISO / Security Analyst review

Recording which platform each new account came from ([decisions § 2350](../architecture/decisions.md), migration `20271110000001`) ships closed: no migration writes the `signup_source` row of `private.feature_flags`, so no sign-up sends `signup_source` metadata and the `auth.users` trigger records nothing. The browser still keeps the tab's first touch in sessionStorage (`threkir.signup_source`), which never leaves it while the gate is closed. In order:

1. CISO / Security Analyst: confirm the sessionStorage entry needs no cookie consent (first-party, per tab, sent only with a sign-up the person submits; listed on `/cookie-notice` § 2), and that legitimate interest fits the purpose row the privacy policy's § 3 now carries; update [dpia.md](../compliance/dpia.md) if it is a new purpose. Counsel reviews the added privacy-policy text (§ 2 "How you found us", § 3 row, § 7 retention). [sub-processors.md](../compliance/sub-processors.md) does not change: no vendor is involved.
2. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('signup_source', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; recording stops at once and recorded rows stay with their accounts.
3. Reading the counts: `select day, source, signups from private.signup_sources_daily where day >= current_date - 30 order by day desc, signups desc;` in the same SQL editor. Accounts from before step 2 count as `unknown`.

### Display name from the sign-in provider — after the CISO + counsel review

Filling an empty `display_name` from the name Google or Apple supplied ([decisions § 2365](../architecture/decisions.md), migration `20271111000002`, issue #1300 BUG-013) ships closed: no migration writes the `display_name_from_provider` row of `private.feature_flags`, so new profiles stay unnamed until the person types a name, as before. Mobile already writes an Apple sign-in's name to the user metadata as `full_name`; nothing reads it while the gate is closed. In order:

1. CISO + counsel: confirm that showing club members, attendees and public-profile viewers the provider name by default is acceptable, and that the backfill (step 3) may name accounts that never typed one. Update the privacy policy's § 2 "Account" line, which today calls the display name optional and typed by the person, to say a Google / Apple sign-in supplies it and it can be changed or cleared in Settings → Account. No sub-processor changes.
2. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('display_name_from_provider', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; names already filled stay.
3. Once, in the same SQL editor: `select private.backfill_display_names_from_provider();` — returns how many existing profiles it named. Skip it if step 1 limited the change to new sign-ups.

### Public plan share ("Train with me") — after the CISO / Security Analyst review

The logged-out `/share/plan/[id]` page ([training.md § Train with me](../features/training.md#train-with-me--public-plan-share-page), decisions § 2262, migration `20271103000002`) ships closed: no migration writes the `public_plan_share` row of `private.feature_flags` (`seed.sql` opens it for local and CI only), so `public_plan_share(p_id)` answers null and "Copy share link" stays hidden. From training.md's checklist:

1. CISO / Security Analyst review of the redacted projection (what an anonymous reader sees, and that the author credit honours private profiles and blocks), recorded with the sign-off date.
2. `terraform apply` for the `/share/plan/*` CloudFront behaviour and the `plan` upstream alarm, then a `web@*` deploy so the `share-entity` zip carries the dispatcher branch (see [the share-entity apply](#share-entity-behaviours-and-memory--terraform-apply-before-the-web-release) below).
3. `insert into private.feature_flags (name, enabled) values ('public_plan_share', true) on conflict (name) do update set enabled = true;`

### Flyover video and keyless terrain — operator and security sign-off

The 3D course preview and its video export (decisions § 2251, § 2259) add two third-party map sources and one fail-closed build flag.

1. **Operator:** confirm that the MapTiler plan's terms permit its terrain and imagery in a published, marketing video before setting `PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED` (a `release-web.yml` secret, default off; [apps/web/deployment.md](../../apps/web/deployment.md)) and, in the same release, the mobile `FLYOVER_VIDEO_MAPTILER_ENABLED` define. Until both are set, "Export video" is not offered on threkir.com and the phone hides its run **Video** share style (decisions § 2270): the export never falls back to OSM's public tile servers, whose usage policy does not allow frame-by-frame rendering. The on-screen preview uses MapTiler either way.
2. **CISO / Security Analyst:** confirm the classification of AWS Open Data Terrain Tiles (`elevation-tiles-prod.s3.amazonaws.com`) as a browser-side data recipient ([sub-processors.md](../compliance/sub-processors.md)): a public bucket outside our AWS account, so no DPA covers it, and each tile request carries the viewer's IP and the tile that locates the course. The preview and the export reach it only when no MapTiler key is set, which the release build refuses.
3. **CISO / Security Analyst:** review the preview's consent wording, which is the gate in front of every terrain request: its own card ("Load the 3D preview?", "The preview loads map and terrain tiles from MapTiler, our map provider, which receives your IP address", button **Load preview**, `coursePreview.consent*` in every locale) shown when cookie consent has not been accepted and, on the logged-out share pages, on every view regardless, the role the 2D maps' "Load map" placeholder plays. `consent_guards.test.ts` binds any caller of `resolveTerrainSource` to it.

### Share-entity behaviours and memory — `terraform apply` before the web release

PR #1271 changes `infra/modules/web-stack`, and the `web@*` release that carries the new share pages needs it applied first:

- three `ordered_cache_behavior` blocks routing `/share/plan/*`, `/share/challenge/*` and `/og/challenge/*` to the `lambda-share-entity` origin (`main.tf`);
- the `share-entity` Lambda at 512 MB instead of 256, because `/og/challenge/<id>.png` rasterises with `@resvg` (`main.tf`);
- `plan` and `challenge` entries in the share upstream-unreachable alarms (`alarms.tf`);
- `https://elevation-tiles-prod.s3.amazonaws.com` added to the CSP's `img-src` and `connect-src` for the keyless terrain rung (§ 2251).

Run `terraform plan` in `infra/envs/prod` (and `preview`), check that only these change, apply, then cut the `web@*` tag so the `share-entity` zip carries the plan and challenge dispatcher branches. The plan and challenge pages stay dark behind their own flags after the apply.

### Head-to-head read — release review item

The `head_to_head(kind, target, friend?)` RPC (migration `20271104000003`, decisions § 2267) ships **without** a feature flag, because it returns only a subset of what the caller can already read: mutual follows, no block, a public non-hidden friend profile, and public, non-DNF runs on both sides, with every refusal the same empty result and no `personal_records`, track, age or gender read. It goes live with the `db push` and the web and mobile releases that carry it. The CISO / Security Analyst reviews it as a normal release item before those releases: the function's predicates, that its refusals are indistinguishable, and the pgTAP file that pins each rule.

### Route-photo orphan sweep — after the CISO / Security Analyst review

The server-side sweep of route-photo bytes no `route_photos` row references ([retention.md](../compliance/retention.md), decisions § 2305, migration `20271106000020`) ships closed: no migration writes the `route_photo_orphan_sweep` row of `private.feature_flags`, so the delete trigger queues nothing, the nightly `enqueue-route-photo-orphan-sweep` cron queues nothing, and `route_photo_orphan_paths` answers empty even to a job queued by hand. Until it opens, the § 2293 gap stands: bytes a client sweep missed, and a club admin's delete of someone else's photos, stay in the bucket until account deletion. The job deletes user bytes, so a wrong predicate deletes live photos; the review is of `route_photo_orphan_paths` (what counts as referenced: `storage_path`, `thumb_512_path`, the upload behind a mobile placeholder row, and the 24-hour grace on the backstop) and `handler_route_photo_orphan_sweep.go` (Storage API erase, per-run bound, counts-only logging). Before opening, a read-only dry look at what the first night would erase: `select count(*) from storage.objects o where o.bucket_id = 'route-photos' and greatest(o.created_at, o.updated_at) < now() - interval '24 hours' and not exists (select 1 from route_photos rp where rp.storage_path = o.name or rp.thumb_512_path = o.name or (rp.storage_path = '' and o.name like rp.owner_id::text || '/' || rp.id::text || '.%'));`. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('route_photo_orphan_sweep', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; a job already queued then finds an empty worklist and erases nothing. The worker must be on a build that routes `route_photo_orphan_sweep` before the flag opens, or the jobs fail as an unknown kind and retry out.

### Coach run map — after the CISO / Security Analyst review

A linked coach's clipped view of the athlete's run map ([coach_roster.md § Coach run map](../features/coach_roster.md#coach-run-map-decisions--1968), decisions § 1968) ships closed: no migration writes the `coach_run_map` row of `private.feature_flags`, so a coach keeps run rows and stats only, as before. Open it only after the CISO / Security Analyst has reviewed the `coached_runs` view and the coach branch of `clip-public-track` — then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('coach_run_map', true) on conflict (name) do update set enabled = true, updated_at = now();`. Closing it again is the same statement with `false`; both clients stop drawing the map and the view empties at once.

### Safety-contacts live audience — after the CISO and counsel reviews

A live share that runs on the runner's confirmed safety contacts only, with no public flip ([safety.md § Safety-contacts-only audience](../features/safety.md#safety-contacts-only-audience-2026-10-15-decisions-1964), decisions § 1964 – § 1966), ships closed: no migration writes the `safety_audience` row of `private.feature_flags` (`seed.sql` opens it for local and CI only), so every client keeps the old explicit, public live share. Opening it also turns the automatic live share on by default for a runner who armed an overdue window or the off-route alert (§ 1965), so the reviews cover that default too. Order, from safety.md's checklist:

1. CISO review of the per-contact capability links, the admission predicate, the 48 h window, the fragment transport and the default-on rule.
2. Counsel review of the same, plus the contact-facing copy in all seven locales (the `/live/[id]` notice and closed-link state, and the overdue / off-route email and SMS that now carry a personal link).
3. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('safety_audience', true) on conflict (name) do update set enabled = true, updated_at = now();`. The same statement with `false` is the rollback; the default reverts for everyone who never touched the switch, and every outstanding link stops admitting on its next poll.

### Drive this course — after counsel signs off on the safety notice

Drive this course ([course_drive.md](../features/course_drive.md), decisions § 2380) is built on web and mobile behind `PUBLIC_COURSE_DRIVE_ENABLED` (a `release-web.yml` secret) and `COURSE_DRIVE_ENABLED` (a mobile dart-define), both default off.

1. **Counsel:** review the driver safety notice (`courseDrive.notice` on web, `courseDriveNoticeBody` in the mobile ARBs, every locale) and the help guide's caution (`drive-a-course`), per decisions § 150. Loop in the CISO / Security Analyst for the record.
2. **Operator:** a real drive per [manual_testing.md](../testing/manual_testing.md) ("Drive this course (real drive)"), including that Google's app takes nine stops.
3. Set both flags together (web secret, then the mobile define in the next store build).

### Sign-up consent from metadata — after the legal memo and owner approval

An email sign-up's 16+ and Terms stamps are written to `user_profiles` from its sign-up metadata when the account is confirmed (`private.stamp_signup_consent()`, migration `20271023000001`, decisions § 2238, #1229). Until then such accounts meet the consent gate again on their first sign-in. The trigger ships closed: no migration writes its flag row, so prod behaves exactly as before.

1. A `legal-researcher` memo on capturing the Art 8 / terms evidence from sign-up metadata, and owner approval of it recorded on #1097.
2. Then, in the prod SQL editor: `insert into private.feature_flags (name, enabled) values ('signup_consent_from_metadata', true) on conflict (name) do update set enabled = true, updated_at = now();`. The same statement with `false` is the rollback. Accounts already stamped keep their stamps, and the gate asks anyone who has none.

### AI features beside the Coach — paired flags, one sign-off each

Each ships default off with two halves: a `PUBLIC_*` flag in the web build (`release-web.yml`, [apps/web/deployment.md § fail-closed feature gates](../../apps/web/deployment.md)) and an unprefixed key in the coach Lambda's sops file (`coach_config_keys`). Set both halves together, and only after the sign-off in the right-hand column. Each also needs `PUBLIC_COACH_ENABLED`.

| Feature | Web flag | Lambda key | Sign-off before flipping |
|---|---|---|---|
| AI plan assistant on `/plans/new` (decisions § 1930) | `PUBLIC_AI_PLAN_ENABLED` | `AI_PLAN_ENABLED` | owner + counsel on superseding § 12 in part; counsel / CISO on the v3 AI-disclosure copy |
| Adjust with AI on `/plans/[id]` and the plan-edit card in the Coach chat (§ 1979 – § 1981, § 2230) | `PUBLIC_AI_PLAN_EDIT_ENABLED` | `AI_PLAN_EDIT_ENABLED` | owner + counsel on § 1979; counsel / CISO on the v4 AI-disclosure copy |
| Log from a photo on `/nutrition/log` (§ 1972 – § 1973) | `PUBLIC_PLATE_PHOTO_ENABLED` | `PLATE_PHOTO_ENABLED` | counsel / CISO on the v5 AI-disclosure copy; owner on the vision spend |
| Coach fuelling handoff to `/nutrition/fuel` (§ 1975) | `PUBLIC_COACH_FUEL_ENABLED` | `COACH_FUEL_ENABLED` | owner + counsel ([race_fueling_plan.md](../features/race_fueling_plan.md) pre-deploy checklist); no new disclosure rung |

The disclosure copy is **not** behind these flags. The disclosure migrations (`20270816000001` v3, `20270825000001` v4, `20270826000003` v5) apply with the next `db push`, and the web and mobile releases that carry them show every bullet up to v5 in the AI disclosure (`AiDisclosureNotice.svelte`, `widgets/ai_disclosure_notice.dart`) and record a v5 acceptance, whatever the flags say. So the v3 – v5 copy sign-offs gate those releases, not only each flag flip.

### Adaptive fitness gate — after the CISO / Security Analyst review

The CTL/ATL/TSB direction gate on the adaptive re-plan (decisions § 144, § 1977) is built on web and mobile and off. Flip `PUBLIC_ADAPTIVE_FITNESS_GATE` (web build) and `ADAPTIVE_FITNESS_GATE` (the mobile dotenv, [apps/mobile_android/deployment.md](../../apps/mobile_android/deployment.md)) only after the CISO / Security Analyst signs off on health-derived load feeding a prescription. § 1977 records the verification behind the request.

### Weight-based fluid — after the CISO / counsel review

The "Fluid from body weight" toggle on the roadbook and `/nutrition/fuel` (decisions § 1976) is built on web and mobile and off. Off, neither surface reads a body weight, the toggle is hidden, and the flat fluid rate stands whatever `?bw=1` a link carries. Flip `PUBLIC_WEIGHT_FLUID_ENABLED` (web build) and `WEIGHT_FLUID_ENABLED` (the mobile dotenv, [apps/mobile_android/deployment.md](../../apps/mobile_android/deployment.md)) together, only after its [pre-deploy checklist](../features/race_fueling_plan.md) item lands: the CISO / counsel review of a new Art 9 use of body weight against the health-data consent copy. If the review finds the consent copy lists its uses exhaustively, fuelling is added to it before the flip.

### Upcoming parkruns — after parkrun's written permission

The parkrun leg of `race-listings-sync` and `race-listings-sweep` (decisions § 1958) is off unless the function secret `PARKRUN_EVENTS_ENABLED` is the literal `true`; off, the sweep makes no parkrun request. Get parkrun's written permission to list its events (issue #1148 step 1), land whatever it asks for (attribution, link wording; see the [followups](../product/followups.md) entry), then `supabase secrets set PARKRUN_EVENTS_ENABLED=true`. It rides the RunSignUp sweep below, so that sweep must be armed first. Unset it to turn the leg off again.

### Security emails — two auth settings, no new secret

The password-changed and new-device notices ([email.md § Security emails](../features/email.md#security-emails)) ship with the code, and the new-device half is live as soon as `20270804000002` applies — it rides the worker's existing `SMTP_HOST` / `APP_BASE_URL`, and its `prune-sign-in-devices` pg_cron is created by the migration. The password-changed half needs two operator settings that `config.toml` does not reach: turn on the **password changed** security notification on the hosted project (Dashboard → Auth → Emails, or the Management API `config/auth` field `mailer_notifications_password_changed_enabled`), and set `APP_BASE_URL` (the web origin) on the `auth-email` function so the notice carries its Reset password button. Neither is a credential. Verify by changing a test account's password and reading the mail.

### RunSignUp race calendar — arm the sweep (one Vault entry)

The RunSignUp legs need no key ([decisions § 1903](../architecture/decisions.md)), but the calendar only fills once the five-minute sweep is armed ([§ 1902](../architecture/decisions.md)). Migration `20270805000002` schedules `race-listings-sweep` and its invoker calls nothing until both Vault secrets exist, so an unarmed deploy is inert rather than broken.

1. Deploy the function: `supabase functions deploy race-listings-sweep` (its `verify_jwt = false` comes from `config.toml`). `CRON_SECRET` must already be set as a function secret — `refresh-tokens` and `events-refund-sweep` use the same one.
2. Confirm the `cron_secret` Vault entry exists (name only): `select name from vault.secrets where name = 'cron_secret';`.
3. Add the URL entry in the SQL editor: `select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/race-listings-sweep', 'race_listings_sweep_url');`.
4. Verify one run by hand: `select public.invoke_race_listings_sweep();` returns a request id, and `select status_code, left(content::text, 200) from net._http_response order by id desc limit 1;` shows `200` with a `window` and `synced` / `unplaced` counts. A `complete: false` (and a `window filled the page` log) means a 14-day window held 500 races — narrow `SWEEP_WINDOW_DAYS`.

### Club verification re-check — arm the schedule (one Vault entry)

Migration `20271120000004` schedules `club-verification-recheck` hourly ([decisions § 2398](../architecture/decisions.md)); its invoker calls nothing until both Vault secrets exist, so verified clubs are simply not re-checked until this is done. The owner-facing `club-verification` function needs nothing beyond the deploy.

1. Deploy both functions: `supabase functions deploy club-verification` and `supabase functions deploy club-verification-recheck` (the latter's `verify_jwt = false` comes from `config.toml`). `CRON_SECRET` is the same function secret the other sweeps use.
2. Add the URL entry: `select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/club-verification-recheck', 'club_verification_recheck_url');`.
3. Verify one run: `select public.invoke_club_verification_recheck();` returns a request id, and the latest `net._http_response` shows `200` with `checked` / `verified` / `failed` / `lapsed` / `skipped` counts.

The email proof needs no new credential: it rides the worker's existing SMTP transport and `APP_BASE_URL`.

### Lambda secrets — one apply, before the next web deploy

[decisions § 1671](../architecture/decisions.md) moved the coach and
generate-route credentials out of their Lambda environments and into a KMS
ciphertext the handler decrypts at cold start. The code is on `main` and the
guard enforces it; the change is **unapplied and unplanned** — no lane in this
repo holds AWS credentials, so `terraform plan` has never run against real
state. Do this under the operator's own SSO profile, preview first:

1. `terraform plan` in `infra/envs/preview`. Expect two new
   `aws_kms_ciphertext` resources and, on `threkir-web-preview-coach` and
   `-generate-route`, `ANTHROPIC_API_KEY` / `SUPABASE_SECRET_KEY` /
   `OPENAI_API_KEY` / `GRAPHHOPPER_API_KEY` / `GRAPH_CYCLE_API_KEY` **leaving**
   the environment and `SECRETS_CIPHERTEXT` + `SECRETS_CONTEXT` arriving.
   `kms_key_arn` must NOT appear on any function — that is a different design
   and it hands the plaintext back (§ 1021 and claim 9 in
   `scripts/check_infra_iam.mjs`).
2. Apply, then deploy the matching web bundle. **Order matters in one
   direction only**: the new code refuses to serve without a bag, so applying
   before the code lands is safe (the old code ignores the blob) and shipping
   the code before the apply is a 503 on `/api/coach` and
   `/api/routes/generate` until the apply completes.
3. Verify the environment no longer carries a key:
   `aws lambda get-function-configuration --function-name threkir-web-preview-coach --query 'Environment.Variables' | grep -c API_KEY` must be `0`.
4. Verify the decrypt works end to end — one `/api/coach` turn on a cold
   container. An `AccessDeniedException` in the function's log means the
   execution role lost its `kms:Decrypt` on the env's secrets CMK.
5. Repeat for `prod`. Rotating a secret afterwards is `bin/secret-set.sh` **plus
   a re-apply** — the blob is a resource, so a function holding the old one
   decrypts the old value.

### Legal pages — before public launch

The legal pages (`/privacy`, `/terms`, `/cookie-notice`, `/health-data-notice`, plus the
store-facing `/delete-account` instructions page — decisions §247) are complete text
(decisions §243); what remains is operator work, not code:

1. Counsel review of the four pages (plus the docs under `docs/compliance/`).
2. ~~Fill the operator facts in `apps/web/src/lib/legal/operator.ts`~~ — **decided 2026-10-06**
   (issue #1061, M6): governing law is Virginia; no postal address is published and no Art 27 EU / UK
   representative is appointed, recorded as `NOT_PROVIDED` so the pages state it rather than showing
   "pending". Counsel review (item 1) covers this decision too.
3. Art 27 EU + UK representatives — **optional, not appointed** (see item 2). If the EU or UK
   becomes a launch market, appoint them (vendors + process in
   [docs/compliance/eu-representative.md](../compliance/eu-representative.md)) and replace the
   `NOT_PROVIDED` values in the same file. Until then, consider excluding EU / UK countries from App
   Store Connect and Play availability.
4. Create the `dmca@threkir.com` mailbox/alias and register the DMCA agent with the US Copyright
   Office (the Terms already name the address).
5. Confirm each sub-processor DPA is executed (list in
   [docs/compliance/sub-processors.md](../compliance/sub-processors.md)).
6. Enter `https://threkir.com/delete-account` as the **Delete account URL** in the Play Console
   Data safety form (and as the account-deletion link in App Store Connect). The page is live and
   pinned by `tests-e2e/legal/pages.spec.ts`; this item is just the console data entry.
