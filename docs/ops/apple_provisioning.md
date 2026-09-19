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

**App Store Connect is not where any of steps 1–13 happen.** Its "Add Apps"
button creates the distribution listing, and its Bundle ID dropdown is
populated from step 3 — so it cannot be done first, and it unblocks neither
push nor sign-in. Everything Apple-side below is at
<https://developer.apple.com/account>, a different site; step 1 opens with the
distinction because it is the one that costs people an afternoon.

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

### Two different websites, one Apple ID

This trips everyone once. The membership spans two separate sites that share a
login and share almost no navigation:

| Site | What lives there |
|---|---|
| **developer.apple.com/account** | Membership details, Identifiers, Keys, Certificates, Profiles, Services — **everything in steps 1–7 and 10** |
| **appstoreconnect.apple.com** | App records, TestFlight, pricing, Users and Access — **step 14 only** |

If the page you are on has a top bar reading *Apps / Xcode Cloud / Trends /
Reports / Business / Users and Access*, you are in App Store Connect and
nothing in this runbook is reachable from it. There is no "Membership details"
there, under any menu.

### Getting to it

Go to **<https://developer.apple.com/account>** directly. Bookmark that exact
URL — `developer.apple.com` without `/account` is the marketing site, and its
"Account" link bounces through a sign-in that sometimes lands you back on the
marketing page.

The landing page is a list of named sections. Apple's own ordering is:

1. Program resources
2. Developer profile
3. Email preferences
4. **Membership details** ← this one
5. Device reset date
6. Code-level support
7. Automatic signing controls
8. Agreements

Open **Membership details**. It carries the **Team ID**, your role, the
**renewal date**, and the contact address.

### What you are copying

The Team ID is **10 characters, uppercase letters and digits**, e.g.
`A1B2C3D4E5`. Copy it verbatim — it is case-sensitive and steps 6, 7 and 9 all
reject a near-miss with an error that names something else.

It is **not** the long numeric string beside your name in App Store Connect's
header (that is a provider/content-provider id), and **not** the App Store
Connect API "Issuer ID" (a UUID with dashes).

### If Membership details is not there

- **The landing page offers "Enroll" or "Join the Apple Developer Program"** —
  that Apple ID has no active membership. Check you are signed in as the
  account that paid; enrollment and App Store Connect access can sit on
  different Apple IDs if the purchase was made from one and the invite accepted
  on another.
- **You have more than one team** — the selector is at the top right. An
  Individual membership shows your own name as the team.
- **Still nothing** — `https://developer.apple.com/account/resources/certificates/list`
  goes straight to Certificates, Identifiers & Profiles and shows the team name
  and id in its header. If that page loads, the membership is active and only
  the landing page is being odd.

### Then set the reminder

Put the **renewal date** in Bitwarden with a reminder **~3 weeks before**.
Renewal is Account-Holder-only and auto-renew is widely reported to fail
quietly. An expired membership pulls every app from the App Store **and** locks
Certificates, Identifiers & Profiles — nothing ships and no key can be rotated
until it is paid. Whether an existing APNs key keeps authenticating through a
lapse is undocumented; do not plan to find out.

None of this is secret — it is account metadata, so Bitwarden, not a sops entry.

**You are not blocked without it.** Steps 2–5 need no Team ID; it is first
wanted at step 6 (the Firebase upload). If Membership details is being awkward,
carry on to step 2 and come back.

## Where steps 2–7 happen

All five live in one place: **developer.apple.com/account** → **Certificates,
Identifiers & Profiles** (under *Program resources* on the landing page, or
straight to <https://developer.apple.com/account/resources>).

Every one starts the same way — **Identifiers** (or **Keys**) in the **sidebar**,
then the **add button (+)** on the **top left**. On an Individual membership
you are the Account Holder, which is the role these pages require.

Two navigation notes that save a hunt:

- The Identifiers list shows **App IDs** by default. To see Services IDs or App
  Groups you already made, use the **pop-up menu on the top right** of the list.
- Capabilities may be split across **Capabilities** and **App Services** tabs.
  Everything this runbook asks for is under **Capabilities**.

## 2. App Group

**Identifiers** → **(+)** → select **App Groups** → **Continue**.

| Field | Value |
|---|---|
| Description | `Threkir active run` |
| Identifier | `group.com.threkir.app.activerun` |

**Continue** → **Register**.

The `group.` prefix is required by Apple and is part of the identifier, not a
label. This is first because an App Group is its own identifier type and
**cannot be created from inside the App ID screen** — step 3's App Groups
checkbox can only select a group that already exists.

The id is **not** `group.com.threkir.app`. The canonical spelling lives in
[`ActiveRunBridge.swift`](../../apps/watch_ios/WatchApp/ActiveRunBridge.swift)
and is declared in `WatchApp.entitlements`; a mismatch compiles, installs, and
silently shares nothing between the phone and the watch.

## 3. App ID `com.threkir.app`

**Identifiers** → **(+)** → select **App IDs** → **Continue** → the type screen
has **App** preselected → **Continue**.

| Field | Value |
|---|---|
| Description | `Threkir` |
| Bundle ID | select **Explicit App ID**, then enter `com.threkir.app` |

**Explicit**, not Wildcard: Push Notifications, Sign in with Apple and App
Groups all require an explicit App ID, and their checkboxes are **disabled**
under a wildcard — which reads as "not available to my membership" rather than
"wrong radio button".

Tick, under **Capabilities**:

- **HealthKit** — leave *Clinical Health Records* off. We read workouts, not records.
- **Push Notifications**
- **Sign in with Apple** → the row grows a **Configure** button → choose
  **Enable as a primary App ID** → **Save**. Step 5's Services ID and step 7's
  key both attach to this App ID as their primary; if it is not primary, neither
  will list it.
- **App Groups** → **Configure** → select `group.com.threkir.app.activerun` →
  **Continue**. **Ticking the box alone assigns nothing** — the group has to be
  chosen in that modal.

Do **not** tick:

- **Background Modes** — not a portal capability at all. It lives in
  `Info.plist`'s `UIBackgroundModes`, already committed and guard-enforced by
  `scripts/check_ios_native_declarations.mjs`
  ([decisions § 742](../architecture/decisions.md)).
- **Maps** — `com.apple.developer.maps` registers a *routing* app that publishes
  directions coverage. The watch mini-map draws our own polyline through MapKit
  and needs no capability.

**Continue** → review → **Register**.

## 4. Watch App ID

Same flow as step 3.

| Field | Value |
|---|---|
| Description | `Threkir Watch App` |
| Bundle ID | **Explicit App ID** — `com.threkir.app.watchapp` |

Capabilities: **HealthKit** and **App Groups** (Configure → the same group).
Nothing else — the watch does not sign in or receive its own pushes. This is
the side that actually declares the group today; the phone's
`Runner.entitlements` carries no app-group entitlement yet.

## 5. Services ID `com.threkir.web`

The web half of Sign in with Apple, and a **separate identifier type** from the
App ID — which is why it is not a checkbox on one.

**Identifiers** → **(+)** → select **Services IDs** → **Continue**.

| Field | Value |
|---|---|
| Description | `Threkir web` |
| Identifier | `com.threkir.web` |

**Continue** → **Register**.

**Now click it again in the list** (Services IDs are hidden behind the pop-up
menu at the top right). The configuration only exists on an already-registered
Services ID — this is the step people miss, because registering it looks
finished.

Tick **Sign in with Apple** → **Configure**. In the modal:

| Field | Value |
|---|---|
| Primary App ID | `com.threkir.app` (step 3) |
| Website URLs → Domains and Subdomains | `<project-ref>.supabase.co` |
| Website URLs → Return URLs | `https://<project-ref>.supabase.co/auth/v1/callback` |

Both are comma-delimited lists; one entry each is right here. `<project-ref>`
is the subdomain in your Supabase dashboard URL.

**Done** → **Continue** → **Save**.

**The return URL is Supabase's, not ours.** The browser goes to Apple and back
to GoTrue, which mints the session; our own origin never receives the Apple
callback. Two consequences:

- **Apple refuses `http://`**, so there is no localhost entry and no local stack
  can exercise this flow. That is why `PUBLIC_APPLE_AUTH_ENABLED` stays unset in
  `.env.development` while the Google flag is on —
  see [`web_app_auth.md`](../features/web_app_auth.md).
- **You should not be asked to verify a domain here.** Apple's
  `apple-developer-domain-association.txt` check applies to domains *you*
  control, and this one is Supabase's. If Apple demands verification you have
  entered `threkir.com` — which would also fail, because our www→apex 301 and
  the CloudFront behaviours do not guarantee a `.well-known` path answering 200
  `text/plain` with no redirect, and Apple rejects all three. Step 10 is the one
  place `threkir.com` legitimately appears.

## 6. APNs key → Firebase

**Keys** in the sidebar → **(+)**.

| Field | Value |
|---|---|
| Key Name | `Threkir APNs` |
| Services | tick **Apple Push Notification service (APNs)** — and nothing else |

Then click **Configure** next to APNs. Two choices, and both matter:

- **Key Type: Team Scoped.** Topic Specific binds the key to named bundle ids,
  which buys nothing here and breaks the day a second app is added. Firebase
  expects a team-scoped key.
- **Environment: the option covering both Sandbox and Production.** If forced to
  pick one, pick the one that includes Production. A `development`-signed build
  mints a token only the sandbox host accepts, and a TestFlight build only the
  production host — and FCM routes each token to the right host on its own, so
  the key must be able to serve both.

**Continue** → review → **Confirm** → **Download**.

Record the **Key ID** (10 characters) from the key's page. **The Download
button works once** — the key is not stored in your account, and a disabled
Download button means it was already downloaded. If you lose it, revoke and
make a new one.

Then, in the **Firebase** console — *not* Fly, and not the worker:

**Project settings** → **Cloud Messaging** tab → the **iOS app** card → **APNs
authentication key** → **Upload**. Supply the `.p8`, the **Key ID**, and the
**Team ID** from step 1.

**Why Firebase and not the worker.** iOS is delivered *by* FCM: the clients
register an FCM registration token, and a direct APNs POST addresses a
different kind of token entirely — the mismatch that made every iOS push report
success while arriving nowhere
([decisions § 1677](../architecture/decisions.md)). What still has to match the
build is the `aps-environment` entitlement, which the pbxproj pins per
configuration ([decisions § 742](../architecture/decisions.md)).

## 7. Sign-in-with-Apple key

**Keys** → **(+)** again — a **second, separate key**. Do not add Sign in with
Apple to the key from step 6: Firebase and Supabase hold these separately, and
one file cannot be downloaded twice.

| Field | Value |
|---|---|
| Key Name | `Threkir Sign in with Apple` |
| Services | tick **Sign in with Apple** → **Configure** → Primary App ID `com.threkir.app` → **Save** |

**Continue** → **Confirm** → **Download**. Record this **Key ID** too — it is a
different 10 characters from the APNs one, and step 9 wants this one.

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
