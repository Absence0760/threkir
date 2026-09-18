# Native push (FCM / APNs) — implementation plan

> **Status:** Built 2026-06-19, **gated on operator credentials.** Specced
> 2026-06-15; the plan below was executed as written, so it now doubles as the
> design record for shipped code. On disk: migration
> `apps/backend/supabase/migrations/20270212_001_native_push_channel.sql`, the
> worker handler `apps/job_worker/internal/handler_native_push.go` + the
> `apps/job_worker/internal/nativepush/` sender (`fcm.go` + `apns.go`), the
> `device_tokens` CRUD on `packages/api_client/lib/src/api_client.dart`, and the
> mobile bridge `apps/mobile_android/lib/push_messaging_bridge.dart` +
> `firebase_push_messaging.dart` (byte-identical iOS twin).
>
> **The credential gate is real and still open.** Going live needs the worker
> env (`FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID` for Android,
> `APNS_KEY_P8` + `APNS_KEY_ID` + `APNS_TEAM_ID` + `APNS_TOPIC` for iOS) plus the
> per-app config files (`google-services.json` / `GoogleService-Info.plist`).
> Unset → `nativepush.NewSender` returns `(nil, nil)`, `Worker.NativePush` stays
> nil, and `handleNativePush` finishes each job **without** stamping
> `native_push_sent_at`, so the rows stay pending for a later credentialed
> deploy. Provisioning those credentials is the only remaining step.
>
> Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Operator provisioning (the credential gate)

Everything below is the human half of this feature. The code is on `main`; what
follows is the only reason nothing is delivered. The build-side wiring each
artifact needs is already in place — the Gradle plugin, the Xcode target
membership, the two release-workflow decode steps, and the web build's
`PUBLIC_VAPID_PUBLIC_KEY` — so provisioning is now paste-and-verify rather than
paste-and-then-discover-nothing-reads-it.

### Where each artifact lives

Two homes per artifact, mirroring the Android upload keystore
([`apps/mobile_android/deployment.md`](../../apps/mobile_android/deployment.md)):
a **durable** copy in the private estate repo, which survives a lost
workstation, and an **operational** copy in the system that consumes it, which
is write-only and can never be read back.

| Artifact | Durable (estate `threkir/push-credentials.sops.yaml`) | Operational | Read by |
|---|---|---|---|
| `google-services.json` | `google_services_json_base64` | GitHub secret `GOOGLE_SERVICES_JSON_BASE64` | the `google-services` Gradle plugin, at build time |
| `GoogleService-Info.plist` | `google_service_info_plist_base64` | GitHub secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` | the Runner target's Resources phase |
| FCM service-account JSON | `fcm_service_account_json` | Fly secret `FCM_SERVICE_ACCOUNT_JSON` (+ `FCM_PROJECT_ID`) | `nativepush`'s FCM transport |
| APNs `.p8` | `apns_key_p8` | Fly secrets `APNS_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_TOPIC` | `nativepush`'s APNs transport |
| VAPID private key | `vapid_private_key` | Fly secret `VAPID_PRIVATE_KEY` (+ `VAPID_PUBLIC_KEY`, `VAPID_SUBJECT`) | `webpush`'s sender |
| VAPID public key | `vapid_public_key` | GitHub secret `PUBLIC_VAPID_PUBLIC_KEY` | the web build, inlined into every browser bundle |

Neither config file is a secret in Google's sense, and both are gitignored
anyway: this repo is public, and the estate + GitHub-secret pair is what every
other identifier here already uses. The `.p8` is downloadable **once** — Apple
keeps no copy, so the estate entry is the only backup that will ever exist.

A new file in the estate repo needs a `creation_rules` entry in its
`.sops.yaml` or `sops` refuses to encrypt it (fail-closed by design).

### Order of work

1. **Firebase project.** One project serves both apps. Add an **Android** app
   with package `com.threkir.app` and an **iOS** app with bundle id
   `com.threkir.app` — the ids are what the release workflows check before
   building, because a config exported for a different app fails obscurely on
   Android and, on iOS, mints tokens that are delivered to nobody and report no
   error. Download each app's config file.
   **`FCM_PROJECT_ID` is the project *ID*, not the display name.** If `threkir`
   is already taken globally, Firebase appends a suffix (`threkir-4f2c9`) and
   that is permanent; read it off the project-settings page or the
   `project_id` field of either JSON rather than typing the name you chose.
   Stay on the free **Spark** plan — FCM is free at any volume, and Blaze buys
   Cloud Functions we do not use. Leave **Google Analytics off**: FCM does not
   need it and enabling it owes `docs/compliance/sub-processors.md` and the
   privacy policy an entry.
   **None of the Apple work gates this.** A Firebase iOS app needs only a
   bundle id, so the plist can be downloaded before the Developer Program
   enrollment clears; the single Apple-dependent step is uploading the `.p8`
   under Cloud Messaging. Android and browser push can therefore be fully live
   while iOS is still waiting, which is also what the worker's
   `native_push: enabled fcm=true apns=false` boot line means.
2. **FCM service account.** Project settings → Service accounts → generate a
   private key. `FCM_PROJECT_ID` is that JSON's `project_id`. This is what
   signs FCM HTTP v1 sends; the config files do not.
3. **APNs auth key.** Needs the Apple Developer Program (still open in #922).
   Keys → new key with the APNs service enabled; the download is one-time.
   `APNS_TOPIC` is the bundle id, `com.threkir.app`.
   **`APNS_SANDBOX` is not a preference.** A token minted by a build signed
   `development` is rejected by the production host and vice versa — the
   worker holds one setting, so it serves either TestFlight/App Store builds
   (unset) or Xcode-installed builds (`=1`), not both.
4. **VAPID pair** for browser push — `npx web-push generate-vapid-keys`, once,
   ever. The public half goes in **two** places and must match: the worker's
   `VAPID_PUBLIC_KEY` and the web build's `PUBLIC_VAPID_PUBLIC_KEY`. The worker
   derives the public point from the private scalar and refuses to boot on a
   mismatched pair, so the failure it cannot catch is a *web build* carrying a
   third key: browsers then subscribe against a key nothing signs with, and the
   push service answers 403 forever. `check_production_env.mjs` rejects a
   malformed key at release time (the generator prints the private half first).
5. **Set the secrets**, then redeploy each consumer. A GitHub secret reaches a
   binary only through a release build; a Fly secret restarts the worker by
   itself.

### Verifying it, in the order the signal appears

1. **Worker boot log** (`fly logs --app threkir-worker`) — `native_push:
   enabled fcm=true apns=true` and `web_push: enabled`. Anything still reading
   `DISABLED` means that group of secrets did not land; an invalid credential
   exits 2 instead, naming itself.
2. **A device registers.** Sign in on a build made *after* the config file
   landed and a `device_tokens` row appears for that user with the right
   `platform`. No row means the client leg, not the sending leg: on Android,
   the likeliest cause is an AAB built before the secret existed, since the
   Gradle apply is conditional and the release step only warns.
3. **A notification delivers.** Trigger any notification (a kudos is easiest)
   and watch `notifications.native_push_sent_at` / `web_push_sent_at` go from
   null to stamped.
   **There is no historical flood to brace for, and the reason is the enqueue
   trigger rather than the handler.** `enqueue_notification_native_push_job()`
   inserts a job only for a recipient who *already* has an enabled
   `device_tokens` row, and the web sibling only for one whose
   `user_device_settings.prefs` already carries a `push_subscription` — so
   every notification raised before any device registered produced no push job
   at all. What the handlers' don't-stamp-when-unconfigured behaviour protects
   is the narrower window where a device HAS registered and the sender is not
   yet credentialed: those jobs stay unstamped and the first credentialed poll
   delivers them. Registering a device before the credentials land is therefore
   safe in either order, and a fresh project has nothing queued.

### What a local dev needs

Nothing, to build or run: the Gradle plugin is skipped when the file is absent
and the bridge no-ops. To actually exercise push on a device, fetch the config
out of the estate first — for example

```
AWS_PROFILE=threkir sops --decrypt --extract '["google_services_json_base64"]' ../infra-secrets/threkir/push-credentials.sops.yaml | base64 -d > apps/mobile_android/android/app/google-services.json
```

iOS is the one asymmetry: the plist is a member of the Runner target, so an
iOS build **fails** until it is fetched, rather than quietly shipping without
push.

## Goal & user value
Deliver the last device-delivery leg: a push notification to a **locked phone**
(not just the browser, not just email). Build the FCM/APNs sender as a **second
consumer of the existing `notifications` rows** — exactly the sibling-consumer
pattern the shipped `web_push` kind already demonstrates — plus the client-side
device-token registration on sign-in that the `device_tokens` table was created
for but never got a write path. Going *live* is blocked only on operator-
supplied Firebase/APNs credentials; **all credential-independent code ships
now, fail-closed** (nil sender → jobs finish without sending, rows stay
pending), so a later credentialed deploy delivers the backlog.

## What already exists to build on (verified)
- **`notifications` table** is the single source of truth read by the in-app
  bell, the `notification_email` kind, and the `web_push` kind. Each consumer
  has its own `*_sent_at` idempotency column and its own preference gate.
- **`device_tokens` table** — `apps/backend/supabase/migrations/20260506_001_device_tokens.sql`.
  Columns: `id, user_id, platform (check in ('ios','android','web')), token,
  app_version, locale, is_notifications_enabled bool default true, last_seen_at,
  created_at, updated_at, unique (user_id, token)`. **The opt-in flag was
  renamed `notifications_enabled` → `is_notifications_enabled` in
  `20261217_001_f17_naming_uniformity.sql` — use the `is_`-prefixed name in
  all new SQL/Go/Dart; the original migration's column comment and the
  `device_tokens_active` partial index still read the old name in their
  text, but the live column is `is_notifications_enabled`.** The DDL comment
  describes the fan-out and the device-changed-hands semantics. **It has NO
  client write path today** (grep: only the generated `db_rows.dart`
  references it). RLS + owner CRUD policies + the `device_tokens_active`
  (partial, where `is_notifications_enabled`) and `device_tokens_platform`
  indexes already exist in `20260506_001`. Stale-token purge already ships:
  `private.purge_stale_device_tokens()` (60 days of `last_seen_at` inactivity)
  in `20260922_001_data_retention_purge_jobs.sql`.
- **The `web_push` kind — the exact pattern to copy:**
  - Migration `apps/backend/supabase/migrations/20261219_001_web_push_channel.sql`:
    adds `notifications.web_push_sent_at`, extends the `jobs_kind_chk` CHECK
    allowlist, the `enqueue_notification_web_push_job()` AFTER-INSERT trigger
    (one job per recipient **gated on subscription presence** to avoid no-op
    jobs), and the `clear_push_subscription` SECURITY DEFINER prune RPC.
  - Worker handler `apps/job_worker/internal/handler_web_push.go` — load the
    notification, gate on the `push_notifications` pref, load subscriptions,
    send, prune dead endpoints (404/410), defer on 429/5xx, stamp the
    `*_sent_at` guard on every terminal path EXCEPT "sender not configured"
    (leaves the row pending so a later credentialed deploy sends it).
  - Sender package `apps/job_worker/internal/webpush/` (RFC 8291/8292, stdlib +
    `golang-jwt`).
  - Worker plumbing: `apps/job_worker/internal/worker.go` — `WebPushSender`
    interface field (`WebPush`, nil disables), and the `dispatch()` switch
    (`case "web_push"` at worker.go:312).
  - Payload + sent-state types in `apps/job_worker/internal/types.go`
    (`WebPushPayload`, `WebPushSentAt`).
- **Preference:** `user_settings.prefs.push_notifications` (`all|important|off`,
  same shape as `email_notifications`, independent channel) — already the gate
  used by `web_push`; native push reuses the **same** pref (one "push" channel
  covers browser + native, per the docs). Toggle already exists on web
  `apps/web/src/routes/settings/notifications/+page.svelte` + mobile
  `apps/mobile_android/lib/screens/settings_preferences_screen.dart`.
- **Docs:** `docs/features/email.md` — the "Native push (FCM / APNs)" bullet
  under "Planned / not built" explicitly states the design ("Same notifications
  source of truth + sibling-consumer pattern the web_push kind now demonstrates;
  an FCM/APNs sender is another sibling. Blocked on operator-supplied
  Firebase/APNs credentials + mobile firebase_messaging token registration.
  roadmap Phase 4b").
- **Mobile:** no `firebase_messaging` dependency in
  `apps/mobile_android/pubspec.yaml` yet; `packages/api_client` is the only
  Supabase entry point (no `device_tokens` method yet).

## Data model / migrations
One migration, mirroring `20261219_001` (use the next free `YYYYMMDD_NNN` —
**placeholder; assign sequentially at landing** by walking past the highest
date in `ls apps/backend/supabase/migrations/`; latest seen at spec time is
`20270202_001`):

```sql
-- apps/backend/supabase/migrations/2027MMDD_001_native_push_channel.sql

-- 1. per-row send-state guard, sibling of web_push_sent_at / email_sent_at
alter table notifications add column native_push_sent_at timestamptz;

-- 2. extend the jobs.kind allowlist — FULL RESTATE of the legal set (dropping a
--    kind breaks an existing enqueue trigger insert: 23514 at INSERT time)
alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs add constraint jobs_kind_chk check (
  kind in (
    'map_match','token_refresh','strava_event','photo_process',
    'notification_email','lifecycle_email','safety_email','web_push',
    'weekly_digest','native_push'
  )
);
-- (verify the live allowlist at write time — include EVERY kind currently in
--  worker.go dispatch + any migration since this plan was written.)

-- 3. enqueue trigger: notification → native_push job, gated on the recipient
--    having at least one device_tokens row (is_notifications_enabled = true).
--    Mirror enqueue_notification_web_push_job() exactly. Gating on token
--    presence avoids a no-op job per notification for the push-less majority.
create or replace function enqueue_notification_native_push_job()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from device_tokens d
    where d.user_id = new.user_id and d.is_notifications_enabled = true
  ) then
    insert into jobs (kind, payload)
    values ('native_push', jsonb_build_object('notification_id', new.id));
  end if;
  return new;
end $$;
revoke execute on function enqueue_notification_native_push_job() from public;
create trigger trg_notification_native_push
  after insert on notifications
  for each row execute function enqueue_notification_native_push_job();

-- 4. prune-dead-token RPC, sibling of clear_push_subscription. The FCM/APNs
--    "unregistered"/410 response means the token is dead — delete that row.
--    SECURITY DEFINER + service_role-only grant (mirror clear_push_subscription,
--    which revokes from public and grants only to service_role — the worker is
--    the sole caller).
create or replace function clear_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from device_tokens where token = p_token;
end $$;
revoke execute on function clear_device_token(text) from public;
grant execute on function clear_device_token(text) to service_role;
```

**RLS for the client write path:** already in place — `20260506_001` enables
RLS and ships four owner policies (`device_tokens_self_select` / `_self_insert`
/ `_self_update` / `_self_delete`, each scoped to `user_id = auth.uid()`). The
client upsert/select/delete write path is unblocked at the policy level today;
this migration adds **no** new `device_tokens` policy. (If you nonetheless find
RLS missing at write time — e.g. a future schema change dropped it — restore the
four self-scoped policies, do not collapse them into a single permissive
`for all`.)

**Codegen (two-regeneration rule, same commit as the migration):**
- `cd apps/backend && npm run gen:types` (or `pnpm gen:types` from repo root) → `apps/web/src/lib/database.types.ts`
- `dart run scripts/gen_dart_models.dart` (from repo root) → `packages/core_models/lib/src/generated/db_rows.dart`
Both committed; CI `parity-types` enforces. `platform` is already a CHECK union;
the `IntegrationProvider`-style narrow-union TS overlay is optional here (clients
write `'ios'/'android'`, no client enum needed — note it, don't force it).

## Web implementation (canonical)
Native push is a **device-only capability** (physical-exception list, §24): a
browser cannot register an FCM/APNs token. So the **client** leg is mobile-only.
The **server** leg (worker) is shared infra, not a web UI. Web work is minimal:
- No new web UI — the `push_notifications` pref toggle already exists on
  `/settings/notifications`. (Confirm copy still reads as a single "Push" channel
  covering browser + phone; tweak `settings.*` i18n if it implied browser-only.)
- `docs/backend/settings.md` registry note: `push_notifications` now gates
  native push too (no new key).

## Worker implementation (Go — the credential-independent core)
Copy the `web_push` trio:
- **`apps/job_worker/internal/handler_native_push.go`** — `handleNativePush`:
  nil-`NativePush`-sender → log + return nil **without stamping** (rows stay
  pending for a later credentialed deploy); else load the notification
  (`FetchNotificationForNativePush`, add to the backend like
  `FetchNotificationForWebPush`), short-circuit if `native_push_sent_at` set,
  gate on `push_notifications` pref (reuse the same pref-resolution helper the
  web_push handler uses), load `device_tokens` for the user where
  `is_notifications_enabled = true`, send to each, prune dead tokens via
  `clear_device_token` (FCM `UNREGISTERED` / APNs 410), defer (return err) on
  transient 429/5xx, stamp `native_push_sent_at` on every terminal path except
  the nil-sender branch. Title/body come from the shared notification catalogue
  (same source `web_push`'s `push_render.go` uses — reuse it).
- **`apps/job_worker/internal/nativepush/`** — the sender package. Two
  transports behind one `NativePushSender` interface:
  - FCM HTTP v1 (`POST https://fcm.googleapis.com/v1/projects/<id>/messages:send`,
    OAuth2 bearer from the service-account JSON — reuse the existing
    `golang-jwt` like `webpush/` does, no heavy third-party Firebase Admin SDK
    unless the team prefers it; note the trade-off).
  - APNs HTTP/2 (`POST https://api.push.apple.com/3/device/<token>`, JWT `:path`
    auth with the `.p8` key). Android tokens → FCM; iOS tokens → APNs (route on
    `device_tokens.platform`). Decide: route iOS through FCM too (simpler, one
    transport) vs. direct APNs (no Google dependency for Apple) — open question.
- **`apps/job_worker/internal/worker.go`** — add a `NativePush NativePushSender`
  field (nil disables, mirroring `WebPush`), add `case "native_push":
  return w.handleNativePush(ctx, job)` to `dispatch()`.
- **`apps/job_worker/internal/types.go`** — `NativePushPayload {NotificationID}`
  + `NativePushSentAt` on the notification type.
- **Config gating (fail-closed):** the sender is constructed only when the
  operator sets the credentials (e.g. `FCM_SERVICE_ACCOUNT_JSON` / `FCM_PROJECT_ID`
  and/or `APNS_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_TOPIC`). Unset →
  `w.NativePush == nil` → jobs finish done, notification rows stay pending.
  Same posture as `web_push` (VAPID unset) and the email handler (SMTP unset).

## Mobile implementation (Android + iOS twin)
The device-led leg — token registration + foreground/background display:
- **Dependency:** add `firebase_messaging` (+ `firebase_core`) to
  `apps/mobile_android/pubspec.yaml` AND `apps/mobile_ios/pubspec.yaml`
  (twin: pubspecs differ only in `name`/`description` — every dep stays in
  lockstep). Android needs `google-services.json` and iOS needs
  `GoogleService-Info.plist` — **these are operator artifacts; the code
  compiles without live values but won't deliver** (the credential gate;
  document as a deploy checklist item, do not stub the code). The iOS
  `aps-environment` entitlement is **not** one of them: it is a checked-in
  capability declaration, it lives in `Runner.entitlements` resolved through
  the per-configuration `APS_ENVIRONMENT` build setting, and
  `scripts/check_ios_native_declarations.mjs` requires it for as long as
  `firebase_messaging` is a dependency (decisions § 742).
- **`packages/api_client`** — add `registerDeviceToken({platform, token,
  appVersion, locale})` (upsert on `(user_id, token)`) +
  `setDeviceNotificationsEnabled(token, enabled)` + `removeDeviceToken(token)`.
  Route through api_client, not raw `Supabase.instance.client.from(...)`.
- **`apps/mobile_android/lib/push_messaging_bridge.dart`** (new top-level
  service, sibling of `wear_auth_bridge.dart` / `run_notification_bridge.dart`):
  - On sign-in (hook the same auth-state path `wear_auth_bridge` uses, wired in
    `main.dart`): request notification permission (Android 13+ runtime
    `POST_NOTIFICATIONS`, iOS APNs prompt), fetch the FCM token
    (`FirebaseMessaging.instance.getToken()`), call
    `ApiClient.registerDeviceToken(...)` with `platform = Platform.isIOS ? 'ios'
    : 'android'`. Listen to `onTokenRefresh` → re-register.
  - On sign-out: `removeDeviceToken` for the current token (so the next user on
    the device doesn't inherit pushes — matches the device-changed-hands DDL
    comment) and unsubscribe.
  - Foreground display + tap-to-deep-link (`onMessage` / `onMessageOpenedApp` →
    route to the notification's target, reusing the existing in-app
    notification-target routing; `/feed` deep links already exist per
    `apps/web/CLAUDE.md`). Wrap every platform-channel call in its own
    try/catch + `debugPrint` (L4 auxiliary-effect resilience — a push-init
    failure must never break sign-in or any core flow).

    **Shipped 2026-08-05 (issue #666).** The seam existed from the first cut but
    `main.dart` built the bridge without an `onOpenNotification`, so every tap
    opened the app wherever it already was and dropped the target. The wiring
    now is:

    | Piece | Where |
    |---|---|
    | URL → typed target (pure, host-tested, never throws) | `apps/mobile_*/lib/push_target.dart` — `pushTargetFromUrl` |
    | Bridge callback → parked target | `main.dart` `routePushOpen` → the `pendingPushTarget` notifier |
    | Drain + navigate | `HomeScreen._onPendingPushTarget` (listener **plus** a first-frame drain) |
    | Cold start | `PushMessaging.getInitialMessage()`, read once in `attach()` |

    Two things are easy to get wrong here. First, `onMessageOpenedApp` does
    **not** replay the tap that launched a terminated app — that message is
    delivered exactly once via `getInitialMessage()`, so a fix wired only to the
    stream works warm and silently fails cold. Second, the tap can arrive before
    any Navigator exists, which is why the target parks in a notifier that
    HomeScreen drains on its first frame (the same shape `incomingRouteImport`
    uses for a GPX opened from a closed app) rather than navigating inline.

    Targets follow `pathForKind` (`apps/job_worker/internal/mailer.go`):
    `/events/{id}`, `/clubs`, `/clubs/{id}`, `/plans`, `/messages`,
    `/runs/{id}`, `/u/{id}`, `/challenges`, `/notifications`. The mobile club
    and event screens are slug-addressed while the push carries a UUID, so
    `SocialService.fetchClubSlugById` / `fetchClubSlugForEvent` resolve it and
    degrade to the clubs hub on a miss. `/messages` has no mobile surface
    (web-only per §24) and lands on the inbox, as does any unrecognised or
    malformed URL — mirroring `pathForKind`'s own `default:` arm.

    **The web side of the same contract closed in this round.** `/events/{id}`
    and `/notifications` used to 404 on web — the inbox lives at
    `/u/{id}?tab=notifications` and events at `/clubs/{slug}/events/{id}` — so
    both are now thin forwarding routes rather than a change to `pathForKind`
    (an id URL already in a delivered inbox has to keep resolving). `/clubs/{id}`
    is the third: `/clubs/[slug]` falls back to an id lookup and forwards to the
    canonical slug. That last one is a **same-route** param change, so SvelteKit
    reuses the component instead of remounting it and nothing re-runs the page's
    onMount fetch — the forward has to re-enter it by hand or the page sits on
    "Loading club…" forever. `tests-e2e/clubs/id-deep-links.spec.ts` walks all
    three anonymously and asserts the resolved page's title, which is what
    catches a forward that arrives at the right URL with no data behind it.
  - Gate the whole bridge on `firebase_messaging` being initialisable; if
    Firebase isn't configured (no `google-services.json`), `attach()` is a
    best-effort no-op (compiles + runs in dev without credentials).
  - Mirror byte-identical to `apps/mobile_ios/lib/push_messaging_bridge.dart`
    in the same commit; `Platform.isIOS`/`isAndroid` for any platform delta.
- **Native glue:** Android `FirebaseMessagingService` registration in the
  manifest + iOS `AppDelegate` APNs registration. These live outside `lib/`
  (`android/`, `ios/`) so they are *not* twin-shared — each app owns its native
  side. Operator supplies the Firebase config files.
- **Settings:** the `push_notifications` toggle already exists in
  `apps/mobile_android/lib/screens/settings_preferences_screen.dart`; ensure it
  also drives `setDeviceNotificationsEnabled` on the local token (so the
  per-device DDL flag tracks the pref) — keep the universal `push_notifications`
  pref as the channel gate (worker-side) and
  `device_tokens.is_notifications_enabled` as the per-device fan-out filter.
- **Nav:** none — no new screen, no new tab (the mobile bottom nav is unchanged).

## TS↔Dart parity helpers
**None.** The push delivery is server-side Go + native platform SDKs; there is
no pure cross-platform logic to share as a TS↔Dart pair. The pref-resolution
logic lives in the worker (Go) and is exercised by `web_push` already. State
this explicitly so the implementer doesn't manufacture a pair.

## Tests (ship in the same commit as each piece)
- **pgtap (backend):** `apps/backend/supabase/tests/native_push_enqueue_test.sql`
  — inserting a `notifications` row enqueues a `native_push` job **only** when
  the recipient has an enabled `device_tokens` row; no token → no job (mirror
  the web_push enqueue test). Plus `device_tokens_rls_test.sql` — owner CRUD,
  non-owner denied, `clear_device_token` deletes by token.
- **Go (worker):** `apps/job_worker/internal/handler_native_push_test.go` —
  mirror `handler_web_push_test.go` / `handler_notification_email_test.go`:
  nil-sender leaves row pending (unstamped); opted-out stamps without sending;
  dead-token (410/UNREGISTERED) prunes + treated as handled; transient 5xx
  returns an error (retry); successful send stamps `native_push_sent_at`. Use a
  fake `NativePushSender` so no real FCM/APNs call is made.
- **Flutter (mobile, + iOS twin):** `apps/mobile_android/test/push_messaging_bridge_test.dart`
  — with a fake messaging seam: registers token on sign-in, re-registers on
  refresh, removes on sign-out, no-ops gracefully when Firebase is
  unconfigured. Mirror to `apps/mobile_ios/test/`.
- **No web e2e** — there is no web UI change beyond an existing toggle; mobile
  has no e2e by design (`docs/testing/testing.md § What's not covered`).

## i18n keys to add (every web locale + all mobile ARBs)
- Push **titles/bodies are NOT new i18n** — they reuse the shared notification
  catalogue the bell + web_push already render (verify; reuse `push_render.go`).
- Mobile permission-rationale copy may need new ARB keys:
  `pushPermissionRationale`, `pushPermissionDenied` (a non-blocking explainer if
  the user declines). Add to all six ARBs, `flutter gen-l10n`, mirror gen to iOS
  twin.
- If the web `settings.pushNotifications*` strings imply browser-only, update
  copy across `apps/web/src/lib/i18n/locales/{en,de,fr,es,ja,pt-BR}.ts`.

## Docs to update
- `docs/features/email.md` — flip the "Native push (FCM/APNs)" bullet from
  `[ ]` to `[~]` (backend + client built, send gated on credentials); add the
  `native_push` kind to the architecture sibling list + the "Where the code
  lives" + "Production ops" sections (the new env vars).
- `docs/product/roadmap.md` — tick the Phase 4b push bullet to "built, gated".
- `docs/product/parity.md` — push row for android/ios.
- `docs/backend/settings.md` — note `push_notifications` covers native too.
- `docs/architecture/decisions.md` — one entry: "Native push is a third
  notifications-row consumer (`native_push` kind), fail-closed on operator
  FCM/APNs credentials, device_tokens fan-out gated on a per-device enabled
  flag" — sibling to the web_push ADR (§133).
- `apps/mobile_android/CLAUDE.md` + `apps/mobile_ios/CLAUDE.md` — add the new
  `push_messaging_bridge.dart` to the top-level `lib/` file list.

## Gating / compliance
- **Fail-closed on operator credentials.** All credential-independent code ships
  on `main`. The worker sender is nil until FCM service-account / APNs `.p8` env
  vars are set → jobs finish done, rows stay pending → a later credentialed
  deploy delivers the backlog. The mobile client compiles + runs without
  `google-services.json` / `GoogleService-Info.plist` (the bridge no-ops). This
  is the §150 pattern (genuine external-credential blocker for *going live*,
  write everything that doesn't need the secret now). **Not a paywall, not a
  CISO/counsel gate** — push of an already-consented notification is not
  privacy-sensitive new processing; the `push_notifications` pref + per-device
  flag are the user controls. Record the credential provisioning as a
  deploy-time checklist item in `email.md`'s "Production ops". The APNs
  **entitlement** is not part of that: it ships in `Runner.entitlements` and is
  guard-enforced (decisions § 742). What the deploy owes is a distribution
  profile carrying the Push Notifications capability, and a
  `codesign -d --entitlements` check that the exported IPA resolved
  `aps-environment` to `production`.

## Commit plan (ordered, path-scoped per-piece)
1. Migration + codegen + pgtap:
   `git commit -- apps/backend/supabase/migrations/2027MMDD_001_native_push_channel.sql apps/backend/supabase/tests/native_push_enqueue_test.sql apps/backend/supabase/tests/device_tokens_rls_test.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart`
2. Worker sender + handler + dispatch + Go tests:
   `git commit -- apps/job_worker/internal/handler_native_push.go apps/job_worker/internal/handler_native_push_test.go apps/job_worker/internal/nativepush/ apps/job_worker/internal/worker.go apps/job_worker/internal/types.go`
3. api_client device-token methods:
   `git commit -- packages/api_client/lib/...`
4. Mobile bridge + pubspec dep + tests + ARBs + gen (Android + iOS twin):
   `git commit -- apps/mobile_android/lib/push_messaging_bridge.dart apps/mobile_ios/lib/push_messaging_bridge.dart apps/mobile_android/lib/main.dart apps/mobile_ios/lib/main.dart apps/mobile_android/pubspec.yaml apps/mobile_ios/pubspec.yaml apps/mobile_android/lib/l10n/ apps/mobile_ios/lib/l10n/ apps/mobile_android/test/push_messaging_bridge_test.dart apps/mobile_ios/test/push_messaging_bridge_test.dart`
   (native `android/` + `ios/` glue can be a separate commit per app if it grows.)
5. Docs sweep:
   `git commit -- docs/features/email.md docs/product/roadmap.md docs/product/parity.md docs/backend/settings.md docs/architecture/decisions.md apps/mobile_android/CLAUDE.md apps/mobile_ios/CLAUDE.md`

## Open questions — resolved as built (2026-06-19)
1. **Route iOS through FCM or direct APNs HTTP/2?** *Both, as the plan proposed*
   — `nativepush.Sender` routes on `DeviceToken.Platform` (`android` → FCM,
   `ios` → APNs) and either leaf may be nil. A platform with no configured
   transport returns `ErrPlatformNotConfigured`, which the handler treats as
   "leave that device pending", so the credential gate is per-platform.

   **Re-opened 2026-09-18: as built, the two halves disagree about what an iOS
   token is, so iOS delivery cannot work at any credential.** The client
   registers `FirebaseMessaging.instance.getToken()` for both platforms
   (`firebase_push_messaging.dart`), which is an **FCM registration token**;
   `apns.go` then POSTs it to `https://api.push.apple.com/3/device/<token>`,
   where the path wants the **APNs device token** — the thing
   `getAPNSToken()` returns. APNs answers `400 BadDeviceToken`, the handler
   stamps `native_push_sent_at` on that terminal 4xx, and the notification is
   marked sent having gone nowhere. Nothing in the tree catches this: the
   platform split is honest on both sides, the mismatch lives in the word
   "token". Two ways out, and they provision differently:
   **(a)** register `getAPNSToken()` on iOS and keep sending direct — but the
   worker's payload carries no `gcm.message_id`, so whether FlutterFire's
   iOS delegate still feeds `onMessageOpenedApp` (the whole § 1644 deep-link
   path) has to be settled on a device before this can be called fixed;
   **(b)** route iOS through FCM too, with the `.p8` uploaded to the Firebase
   project rather than held by the worker — one token type, one payload
   contract, and the tap path is the one already proven on Android. (b) is the
   recommendation; it costs a Google dependency for Apple delivery, which is
   the only thing (a) was chosen for. Tracked in
   [`followups.md`](../product/followups.md).
2. **Firebase Admin Go SDK vs. hand-rolled FCM HTTP v1 + `golang-jwt`?**
   *Hand-rolled*, matching `internal/webpush` — stdlib plus the already-present
   `golang-jwt`, no Firebase Admin SDK.
3. **One "Push" channel for browser + native, or a separate pref?** *One* —
   `handler_native_push.go` reuses the existing `push_notifications` pref gate,
   with the per-device `is_notifications_enabled` flag filtering the fan-out.
4. **Credentials** — **still open.** Who provisions the Firebase project + APNs
   key, and on what timeline? This is the only thing blocking go-live.

## Sequencing for the implementer (executed as written)
1. Write the migration mirroring `20261219_001` (verify the live `jobs_kind_chk`
   allowlist first), apply locally (`cd apps/backend && supabase migration up`),
   run **both** codegen commands, write the pgtap tests (commit 1).
2. Copy `handler_web_push.go` → `handler_native_push.go`; build
   `internal/nativepush/` (start with FCM HTTP v1); wire `worker.go` +
   `types.go`; write the Go handler test with a fake sender (commit 2).
3. Add the `device_tokens` CRUD methods to `packages/api_client` (commit 3).
4. Add `firebase_messaging` to both pubspecs; build `push_messaging_bridge.dart`
   (token register on sign-in, refresh, remove on sign-out, foreground display,
   L4-wrapped), wire into `main.dart`; mirror to iOS twin; ARBs + gen-l10n;
   Flutter test (commit 4). Operator adds the Firebase config files separately.
5. Docs sweep (commit 5). Run `/check` before each commit; run the
   `audit:twin-parity` + `audit:schema-drift` skills before declaring done.
