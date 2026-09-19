---
name: Apple provisioning runbook
description: The living operator runbook for every artifact derived from the Apple Developer Program — APNs, Sign in with Apple, distribution — with a status ledger that is updated as each step lands.
---

# Apple provisioning — the living runbook

One Apple Developer membership feeds three separate things: **native push**
(APNs), **Sign in with Apple** (web + both mobile twins), and **distribution**
(TestFlight / App Store). They share a Team ID and nothing else, and the order
below is the only one that works — each identifier is a prerequisite for the
next, and two of the artifacts download exactly once.

**This file is the progress ledger.** Update the status table in the same pass
that does the step; every other doc points here rather than restating. The
design records are [`native_push.md`](../features/native_push.md),
[`web_app_auth.md`](../features/web_app_auth.md) and
[`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md).

## Status

Last moved: **2026-09-19**.

| # | Artifact | Where it ends up | State |
|---|---|---|---|
| — | Firebase project `threkir` (both apps) | — | **Done 2026-09-18** |
| — | `google-services.json` / `GoogleService-Info.plist` | GitHub secrets `GOOGLE_SERVICES_JSON_BASE64` / `GOOGLE_SERVICE_INFO_PLIST_BASE64` | **Done 2026-09-18** |
| — | FCM service account | Fly `FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID` | **Done 2026-09-18** — worker boots `native_push: enabled` |
| — | VAPID pair (browser push) | Fly `VAPID_*` + GitHub `PUBLIC_VAPID_PUBLIC_KEY` | **Done 2026-09-18** — shipped in `web@1.7.1` |
| — | Developer Program enrollment | — | **Active** — App Store Connect reachable 2026-09-19 |
| 1 | Team ID + renewal reminder | Bitwarden | ☐ |
| 2 | App Group `group.com.threkir.app.activerun` | Apple portal | ☐ |
| 3 | App ID `com.threkir.app` | Apple portal | ☐ |
| 4 | Watch App ID `com.threkir.app.watchapp` | Apple portal | ☐ |
| 5 | Services ID `com.threkir.web` | Apple portal | ☐ |
| 6 | **APNs key** `.p8` | Firebase → Cloud Messaging | ☐ |
| 7 | **Sign-in-with-Apple key** `.p8` | Supabase (via a generated client secret) | ☐ |
| 8 | Both `.p8` files backed up | estate `threkir/push-credentials.sops.yaml` | ☐ |
| 9 | Supabase Apple provider enabled | Supabase dashboard | ☐ |
| 10 | Email-relay source registered | Apple portal → Services | ☐ |
| 11 | `PUBLIC_APPLE_AUTH_ENABLED` truthy + `web@` tag | GitHub secret + release | ☐ |
| 12 | `mobile_android@` release (picks up the push config) | Play | ☐ |
| 13 | Android Apple dart-defines | `APPLE_SERVICE_CLIENT_ID` + `APPLE_REDIRECT_URI` | ☐ |
| — | App Store Connect app record | App Store Connect | ☐ — **last**, and gates nothing above |

The open rows are `☐` rather than `- [ ]` on purpose: the survey docs grep
`- [ ]`, and [`followups.md`](../product/followups.md) already carries these as
two follow-ups. That file tracks whether the *thread* is open; this table
tracks which *step* you are on. Tick here as you go; close the followups
entries only when a whole thread lands.

**App Store Connect is not where any of steps 1–11 happen.** Its "Add Apps"
button creates the distribution listing, and its Bundle ID dropdown is
populated from step 3 — so it cannot be done first, and it unblocks neither
push nor sign-in. Everything below is at
<https://developer.apple.com/account>.

## The two things that are unrecoverable

- **Each `.p8` downloads once.** Apple keeps no copy. Steps 6 and 7 are
  **two different keys** for two different services; a single key with both
  services ticked is not what either consumer expects, and mixing the files up
  gives one service a key the other needs. Back both up (step 8) the same day.
- **Organization → Individual is not supported.** The membership is Individual;
  converting to Organization later is an in-place upgrade of the same
  membership, which is why Individual-first is the reversible order. See
  [`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md) § One-time setup.

## 1. Team ID and the renewal reminder

**Membership details** (Account → Membership details). Record:

- **Team ID** — 10 alphanumeric characters. Steps 6, 7 and 9 all want it. The
  long number beside your name in App Store Connect's header is *not* it.
- **Expiry date**, into Bitwarden with a reminder ~3 weeks out.

Renewal is Account-Holder-only and auto-renew is widely reported to fail
quietly. An expired membership pulls every app from the App Store **and** locks
Certificates, Identifiers & Profiles — nothing ships and no key can be rotated
until it is paid. Whether an existing APNs key keeps authenticating through a
lapse is undocumented; do not plan to find out.

None of this is secret — it is account metadata, so Bitwarden, not a sops entry.

## 2. App Group

**Identifiers** → **(+)** → **App Groups** → Continue.

| Field | Value |
|---|---|
| Description | `Threkir active run` |
| Identifier | `group.com.threkir.app.activerun` |

First, because an App Group is a separate identifier type and cannot be ticked
on an App ID that does not already have it registered. The id is **not**
`group.com.threkir.app` — the canonical spelling lives in
[`ActiveRunBridge.swift`](../../apps/watch_ios/WatchApp/ActiveRunBridge.swift)
and a mismatch silently shares nothing.

## 3. App ID `com.threkir.app`

**Identifiers** → **(+)** → **App IDs** → **App** → Continue.

| Field | Value |
|---|---|
| Description | `Threkir` |
| Bundle ID | **Explicit** — `com.threkir.app` |

Capabilities to tick:

- **HealthKit** — leave *Clinical Health Records* off; we read workouts, not records.
- **Push Notifications**
- **Sign in with Apple** → **Configure** → *Enable as a primary App ID* → Save.
  This is what step 5's Services ID and step 7's key both attach to.
- **App Groups** → **Configure** → select the group from step 2.

Do **not** tick:

- **Background Modes** — not a portal capability at all. It lives in
  `Info.plist`'s `UIBackgroundModes`, already committed and guard-enforced by
  `scripts/check_ios_native_declarations.mjs`
  ([decisions § 742](../architecture/decisions.md)).
- **Maps** — `com.apple.developer.maps` registers a *routing* app that
  publishes directions coverage. The watch mini-map draws our own polyline
  through MapKit and needs no capability.

## 4. Watch App ID

Same flow. Bundle ID `com.threkir.app.watchapp`, Explicit. Capabilities:
**HealthKit** and **App Groups** (the same group). This is the side that
actually declares the group today.

## 5. Services ID `com.threkir.web`

The web half of Sign in with Apple, and a **different identifier type** from
the App ID — which is why it cannot be a checkbox on one.

**Identifiers** → the type dropdown at the top right → **Services IDs** →
**(+)** → Continue.

| Field | Value |
|---|---|
| Description | `Threkir web` |
| Identifier | `com.threkir.web` |

Register it, then **click it again** — the configuration only appears on an
existing Services ID. Tick **Sign in with Apple** → **Configure**:

| Field | Value |
|---|---|
| Primary App ID | `com.threkir.app` (step 3) |
| Domains and Subdomains | `<project-ref>.supabase.co` |
| Return URLs | `https://<project-ref>.supabase.co/auth/v1/callback` |

`<project-ref>` is the subdomain in your Supabase dashboard URL.

**The return URL is Supabase's, not ours.** The browser is redirected to Apple
and back to GoTrue, which mints the session; our own origin never receives the
Apple callback. Two consequences worth knowing before they surprise you:

- **Apple refuses `http://` outright**, so there is no localhost entry and the
  local stack cannot exercise this flow. That is why
  `PUBLIC_APPLE_AUTH_ENABLED` stays unset in `.env.development` while the
  Google flag is on — see [`web_app_auth.md`](../features/web_app_auth.md).
- **You should not be asked to verify a domain here.** Apple's
  `apple-developer-domain-association.txt` check applies to domains *you*
  control, and this one is Supabase's. If Apple demands verification, you have
  entered `threkir.com` instead — which would additionally fail, because our
  www→apex 301 and the CloudFront behaviours mean a `.well-known` path is not
  guaranteed to answer 200 `text/plain` with no redirect, and Apple rejects all
  three. Step 10 is the one place `threkir.com` legitimately appears.

Save → Continue → Save.

## 6. APNs key → Firebase

**Keys** → **(+)**.

| Field | Value |
|---|---|
| Key Name | `Threkir APNs` |
| Services | tick **Apple Push Notifications service (APNs)** only |

Register, then **Download** — once. Record the **Key ID** (10 chars) shown on
the same page; you need it in a moment. Apple caps an account at two APNs keys,
so do not create spares.

Then, in the **Firebase** console — *not* Fly, and not the worker:

**Project settings** → **Cloud Messaging** → the **iOS app** card → **APNs
authentication key** → **Upload**. Supply the `.p8`, the **Key ID**, and the
**Team ID** from step 1.

**Why Firebase and not the worker.** iOS is delivered *by* FCM: the clients
register an FCM registration token, and a direct APNs POST addresses a
different kind of token entirely — the mismatch that made every iOS push report
success while arriving nowhere
([decisions § 1677](../architecture/decisions.md)). One upload also removes the
sandbox/production problem: a `development`-signed build mints a token the
production APNs host rejects and vice versa, and the worker could only ever
hold one setting for the whole fleet. FCM reads each token's own environment.
What still has to match the build is the `aps-environment` entitlement, which
the pbxproj pins per configuration ([decisions § 742](../architecture/decisions.md)).

## 7. Sign-in-with-Apple key

**Keys** → **(+)** again — a **second, separate key**.

| Field | Value |
|---|---|
| Key Name | `Threkir Sign in with Apple` |
| Services | tick **Sign in with Apple** → **Configure** → Primary App ID `com.threkir.app` → Save |

Register, Download, record its **Key ID**. This one goes to Supabase (step 9),
never to Firebase.

## 8. Back both `.p8` files up

Claude does not handle key material — run this yourself, from **inside** the
estate repo, because `sops` discovers its config from the working directory
rather than from the file path:

```
cd ~/github/infra-secrets && AWS_PROFILE=threkir sops threkir/push-credentials.sops.yaml
```

Add `apns_key_p8` and `siwa_key_p8`, plus their two Key IDs and the Team ID as
plain metadata. A new file needs a `creation_rules` entry in the estate
`.sops.yaml` first or `sops` refuses to encrypt it (fail-closed by design);
from the project repo the same path fails with *"config file not found, or has
no creation rules"*, which reads like a missing rule rather than a missing `cd`.

## 9. Supabase Apple provider

**Authentication** → **Providers** (or Sign In / Providers) → **Apple** →
enable.

| Field | Value |
|---|---|
| Client IDs | `com.threkir.web` **first**, then `com.threkir.app` |
| Secret Key (for OAuth) | a generated client secret — see below |

Order matters in that list: the Services ID must be first, or the web flow and
the native flow route to the wrong client.

**The secret is NOT the `.p8`.** Apple's client secret is an ES256 **JWT**
signed *with* the `.p8` — `iss` = Team ID, `sub` = Services ID, `aud` =
`https://appleid.apple.com`, `kid` = the step-7 Key ID. Supabase's dashboard
has a generator that takes those four inputs plus the `.p8` contents and emits
the JWT; use it rather than pasting the key file.

**Apple hard-caps that JWT at six months.** When it expires every Apple sign-in
starts failing with `invalid_client`, on a working configuration, with nothing
in our logs to distinguish it from a misconfiguration. Put a **calendar
reminder at five months** next to the membership-renewal one from step 1, and
note the expiry date in the estate file beside the key.

## 10. Register the email-relay source

**Certificates, Identifiers & Profiles** → **Services** → **Sign in with Apple
for Email Communication** → **Configure** → add the sending domain.

Skipping this breaks mail to every user who picks **Hide My Email**: they
arrive as `…@privaterelay.appleid.com`, and Apple's relay only forwards from
sources that are registered *and* SPF- or DKIM-authenticated. Everything in
[`email.md`](../features/email.md) — the welcome mail, receipts, event
reminders, the digest — silently stops reaching those accounts.

**Register the Return-Path domain, not the visible From.** Apple checks the
envelope sender (`MAIL FROM` / `Return-Path` / bounce domain). We send through
Resend, which uses its own bounce domain unless a custom MAIL FROM subdomain is
configured, so `billing@threkir.com` in the `From:` header tells you nothing
about what Apple will check. Read the actual `Return-Path:` header off a
delivered message (Mailpit locally, or a real send) before registering, and
register that domain — adding `threkir.com` on the assumption it is the
envelope sender is the failure this paragraph exists to prevent.

## 11. Turn the Apple button on

The web code is done and fail-closed; there is no diff to write
([decisions § 1679](../architecture/decisions.md)).

1. Set the repo secret **`PUBLIC_APPLE_AUTH_ENABLED`** to `true`.
2. Cut a **`web@<version>`** tag.

Both are needed. `release-web.yml` writes `apps/web/.env` from its own `env:`
block and the build reads nothing else, so the secret alone changes nothing —
which is exactly how eight flags sat permanently off until
[§ 1678](../architecture/decisions.md).

## 12. Android release for push

Tag **`mobile_android@<version>`**. The `google-services` Gradle apply is
conditional and `release-android.yml` only **warns** when the config secret is
absent, so any AAB built before 2026-09-18 registers no device token at all —
and a client that never registers is indistinguishable from a broken sender.

## 13. Android's Apple dart-defines

`appleSignInAvailable()` in
[`apple_auth.dart`](../../apps/mobile_android/lib/apple_auth.dart) gates the
Android button on two dart-defines, the way Google's is gated on
`GOOGLE_WEB_CLIENT_ID`:

- `APPLE_SERVICE_CLIENT_ID` — the **same Services ID** from step 5, `com.threkir.web`
- `APPLE_REDIRECT_URI`

iOS needs neither: it takes the native flow off the App ID capability from
step 3.

## Verifying each thread

**Push**, in the order the signal appears:

1. `fly logs --app threkir-worker` → `native_push: enabled` and
   `web_push: enabled`. `DISABLED` means those secrets did not land; an invalid
   credential exits 2 instead, naming itself.
2. Sign in on a build made **after** the config secret landed → a
   `device_tokens` row appears with the right `platform`. No row is the client
   leg, not the sending leg.
3. **Test with a data export, not a kudos.** `push_notifications` defaults to
   `important`, and `importantKinds` in `mailer.go` is exactly
   `event_reminder`, `event_cancel`, `plan_update`, `message`,
   `data_export_ready`, `refund_failed`. A kudos is not in that set, so a kudos
   on a default account produces no push and looks identical to a bad
   credential. A data export is the one an account can trigger unaided, and
   `data_export_ready` passes the default gate. Watch
   `notifications.native_push_sent_at` go from null to stamped.

There is no historical backlog to brace for: the enqueue trigger only inserts a
job for a recipient who *already* has an enabled `device_tokens` row, so every
notification raised before any device registered produced no job at all.

**Sign in with Apple:** the "Soon" pill is gone from `/login`, a real Apple
account lands on `/auth/confirm-age`, and a second sign-in with the same
account reaches `/dashboard` directly.

Two Apple-specific behaviours to expect on that check, neither of them a bug:

- The user's **name is returned only on the very first authorization** for a
  given Apple ID. A later sign-in carries the identity token and nothing else,
  so a name dropped the first time can only be re-asked, never re-fetched.
- **Hide My Email** yields a real, deliverable `@privaterelay.appleid.com`
  address — but anything that assumes an email identifies a person across
  providers will see two accounts for one human.

## When it breaks

| Symptom | Cause |
|---|---|
| `invalid_client` on every Apple sign-in, previously working | The step-9 client secret hit Apple's six-month cap. Regenerate it. |
| `invalid_client` on a brand-new setup | Services ID not first in Client IDs, or the secret's `sub` is the bundle ID rather than the Services ID. |
| Apple asks to verify a domain at step 5 | You entered `threkir.com` instead of the Supabase project domain. |
| No `device_tokens` row on iOS | Expected until step 6 lands — `getToken()` needs an APNs registration first. After it, check the build's `aps-environment`. |
| No `device_tokens` row on Android | An AAB built before the config secret (step 12). |
| `native_push_sent_at` stamped but nothing arrives | Was the pre-§ 1677 defect. If it recurs, read the FCM response body — a 404 prunes the token, a 4xx is logged and dropped. |
| Mail never reaches a `privaterelay` address | Step 10, or the wrong domain registered for it. |
