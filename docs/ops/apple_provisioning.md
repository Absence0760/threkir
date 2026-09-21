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
that does the step; every other doc points here rather than restating. Google
sign-in has a ledger of its own —
[`google_provisioning.md`](google_provisioning.md) — sharing only the Supabase
pages and the release mechanic: its **step 7** is the URL Configuration both
providers read, and it landed 2026-09-21, so the row below is already ticked
for you. Its steps 8 and 9 are the same Release-plus-approval as steps 11 and
12 here. The
design records are [`native_push.md`](../features/native_push.md),
[`web_app_auth.md`](../features/web_app_auth.md) and
[`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md).

## Status

Last moved: **2026-09-21**.

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
| 6 | **APNs key** `.p8` | Firebase → Cloud Messaging | **Done 2026-09-19** |
| 7 | **Sign-in-with-Apple key** `.p8` | Supabase (via a generated client secret) | **Done 2026-09-19** |
| 8 | Both `.p8` files backed up | estate `threkir/push-credentials.sops.yaml` | **Done 2026-09-19** — five values in estate commit `b82fefc`, pushed; the downloaded `.p8` files deleted |
| — | Supabase URL Configuration (Site URL, Redirect URLs, manual linking) | Supabase dashboard | **Done 2026-09-21** — shared; landed with the Google thread |
| 9 | Supabase Apple provider enabled | Supabase dashboard | ☐ |
| 10 | Email-relay source registered | Apple portal → Services | ☐ |
| 11 | `PUBLIC_APPLE_AUTH_ENABLED` truthy + `web@` Release | GitHub secret + release | ☐ |
| 12 | `mobile_android@` release (picks up the push config) | Play | ☐ |
| 13 | Android Apple dart-defines | `APPLE_SERVICE_CLIENT_ID` + `APPLE_REDIRECT_URI` | ☐ |
| 14 | Apple Distribution certificate `.p12` | GitHub `production` env `IOS_BUILD_CERTIFICATE_BASE64` + `IOS_P12_PASSWORD`; estate | ☐ |
| 15 | App Store profiles, phone + watch | GitHub `production` env `IOS_PROVISIONING_PROFILE_BASE64` + `IOS_WATCH_PROVISIONING_PROFILE_BASE64` | ☐ — after steps 3–4, App Group included |
| 16 | App Store Connect API key `.p8` | GitHub `production` env `APP_STORE_CONNECT_API_*`; estate | ☐ |
| 17 | App Store Connect app record | App Store Connect | ☐ — gates nothing above; must exist before step 18 uploads |
| 18 | First `mobile_ios@` release → TestFlight | GitHub Release | ☐ |

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
| **appstoreconnect.apple.com** | App records, TestFlight, pricing, Users and Access — **the unnumbered last row only** |

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
- **App Groups** — tick it and move on. **There is usually no Configure button
  during registration**, and that is expected: the assignment UI needs an App ID
  that exists, so it appears when you *edit* the App ID, not when you create it.
  Assigning the group is the follow-up below.

Do **not** tick:

- **Background Modes** — not a portal capability at all. It lives in
  `Info.plist`'s `UIBackgroundModes`, already committed and guard-enforced by
  `scripts/check_ios_native_declarations.mjs`
  ([decisions § 742](../architecture/decisions.md)).
- **Maps** — `com.apple.developer.maps` registers a *routing* app that publishes
  directions coverage. The watch mini-map draws our own polyline through MapKit
  and needs no capability.

**Continue** → review → **Register**.

### Then assign the App Group — a second pass over the same App ID

Ticking **App Groups** enabled the capability. It did not choose *which* group,
and the App ID is not finished until it has.

**Identifiers** → click **`com.threkir.app`** in the list → scroll to
**Capabilities** → the **App Groups** row now carries an **Edit** (on some
accounts **Configure**) button → click it → tick
`group.com.threkir.app.activerun` → **Continue** → **Save**.

Reopen the App ID once more and confirm the group is named on the row. An App
Groups capability with no group selected is the state that compiles, installs,
signs, and shares nothing between the phone and the watch — there is no error
anywhere in that chain.

**If the Edit button is missing on the second pass too**, the group from step 2
does not exist. Go to **Identifiers**, switch the **pop-up menu at the top
right** to **App Groups**, and check `group.com.threkir.app.activerun` is
listed. Apple offers nothing to select when the list is empty.

## 4. Watch App ID

Same flow as step 3.

| Field | Value |
|---|---|
| Description | `Threkir Watch App` |
| Bundle ID | **Explicit App ID** — `com.threkir.app.watchapp` |

Capabilities: **HealthKit** and **App Groups** — same two-pass shape as step 3,
so register first, then reopen the App ID and **Edit** the App Groups row to
select `group.com.threkir.app.activerun`. Nothing else: the watch does not sign
in and does not receive its own pushes.

**The group matters more here than on the phone.**
`apps/watch_ios/WatchApp/WatchApp.entitlements` declares
`com.apple.security.application-groups` and `ActiveRunBridge.swift` binds that
exact string, so a provisioning profile for `com.threkir.app.watchapp` without
the App Group fails to sign the watch app. `Runner.entitlements` requests no
app group at all yet — the phone half of the bridge is owed code, tracked in
[`followups.md`](../product/followups.md), not a portal step. Assign it on both
App IDs regardless: it costs nothing on the phone and saves a round-trip when
that entitlement lands.

An App Group shares data only when **both** sides declare it, so until the
phone half ships the bridge stays non-functional whatever the portal says.

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
| Website URLs → Domains and Subdomains | `mcbgrgvegqcmdmtraikl.supabase.co` |
| Website URLs → Return URLs | `https://mcbgrgvegqcmdmtraikl.supabase.co/auth/v1/callback` |

Both are comma-delimited lists; one entry each is right here.

The project ref is written out rather than left as a placeholder because it is
**not a secret** — `PUBLIC_SUPABASE_URL` is inlined into every browser bundle,
so it is served to anyone who loads the site. Re-derive it any time with
`curl -s https://threkir.com | grep -o 'https://[a-z0-9]*\.supabase\.co'`
rather than by decrypting anything. If the prod project is ever moved, that
command is the authority and this table is the transcription.

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

## Steps 6 and 7 are TWO keys, and that is the whole count

Not one key with two services, and not three. Apple's Keys page makes one file
per key, each downloadable exactly once, and these two go to different systems:

| | Key Name | Service ticked | Ends up at |
|---|---|---|---|
| **Key 1** (step 6) | `Threkir APNs` | Apple Push Notification service (APNs) | Firebase console |
| **Key 2** (step 7) | `Threkir Sign in with Apple` | Sign in with Apple | Supabase dashboard |

**One service per key.** Ticking both on a single key produces one file that
cannot be in two places — you would upload the same `.p8` to Firebase and
Supabase, and the day you rotate either one you break the other.

The **Configure** button inside step 6 is not a second key. It sets options *on*
key 1.

## 6a. Create the APNs key (at Apple)

**Keys** in the sidebar → **(+)**.

| Field | Value |
|---|---|
| Key Name | `Threkir APNs` |
| Services | tick **Apple Push Notification service (APNs)** — and nothing else |

Click **Configure** on the APNs row. Two options, both on this one key:

- **Key Type → Team Scoped.** Topic Specific binds the key to named bundle ids,
  which buys nothing here and breaks the day a second app is added. Firebase
  expects team-scoped.
- **Environment → the option covering both Sandbox and Production.** If forced
  to one, pick the one including Production. A `development`-signed build mints
  a token only the sandbox host accepts and a TestFlight build only the
  production host, and FCM routes each token to the right host on its own — so
  the key has to serve both.

If there is no Configure button, the account has the older flow and there is
nothing to set. Carry on.

**Continue** → review → **Confirm** → **Download**.

**The Download button works once.** The key is not stored in your account, and a
disabled Download button means it was already downloaded. If you lose the file,
the only repair is to revoke the key and make a new one — which for APNs means
re-uploading to Firebase.

You do not have to transcribe the **Key ID**: Apple names the file
`AuthKey_<KEYID>.p8`, so the 10 characters between the underscore and the
extension are it. It is also on the key's page. Note which of your two keys is
which *now* — both files land in `~/Downloads` with the same shape of name, and
an hour later they are indistinguishable without opening the portal again.

## 6b. Upload it to Firebase

Not Fly, and not the worker.

**Firebase console** → **Project settings** → **Cloud Messaging** tab → the
**iOS app** card → **APNs authentication key** → **Upload**.

Three inputs: the `.p8` from 6a, its **Key ID**, and the **Team ID**
(`33Z28QB3CF`).

**Why Firebase and not the worker.** iOS is delivered *by* FCM: the clients
register an FCM registration token, and a direct APNs POST addresses a
different kind of token entirely — the mismatch that made every iOS push report
success while arriving nowhere
([decisions § 1682](../architecture/decisions.md)). What still has to match the
build is the `aps-environment` entitlement, which the pbxproj pins per
configuration ([decisions § 742](../architecture/decisions.md)).

That is the push thread finished on the Apple side. Nothing in step 7 affects
it.

## 7. The Sign-in-with-Apple key (at Apple, for Supabase)

**Keys** → **(+)** again. A **second, separate key** — do not go back and add
Sign in with Apple to key 1.

| Field | Value |
|---|---|
| Key Name | `Threkir Sign in with Apple` |
| Services | tick **Sign in with Apple** → **Configure** → Primary App ID `com.threkir.app` → **Save** |

**Continue** → **Confirm** → **Download**.

This Key ID is a different 10 characters from the APNs one, and step 9 wants
**this** one — pasting the APNs Key ID into Supabase yields `invalid_client`,
which reads as a bad secret rather than a crossed pair.

## 8. Back both `.p8` files up

Claude does not handle key material — run these yourself, from **inside** the
estate repo, because `sops` discovers its config from the working directory
rather than from the file path. `sops set` reads the file straight in, so no
PEM is hand-pasted and none is retyped:

```
cd ~/github/infra-secrets && AWS_PROFILE=threkir sops set threkir/push-credentials.sops.yaml '["apns_key_p8"]' "$(jq -Rs . < ~/Downloads/AuthKey_<apns key id>.p8)"
```

```
cd ~/github/infra-secrets && AWS_PROFILE=threkir sops set threkir/push-credentials.sops.yaml '["siwa_key_p8"]' "$(jq -Rs . < ~/Downloads/AuthKey_<siwa key id>.p8)"
```

Then `apple_team_id` (`33Z28QB3CF`), `apns_key_id` and `siwa_key_id` the same
way, as plain `'"..."'` JSON strings. They are not secret, but a `.p8` without
its Key ID is unusable and nothing else in the estate records which is which.
A value set this way passes through the shell, so the PEM lands in
`~/.bash_history` and is briefly visible in `ps`; on a machine where that
matters, open the file with a bare `sops <file>` and paste instead.

**A backup nobody pushed is not a backup.** `sops set` leaves the estate repo
dirty and the only durable copy of a once-downloadable key sitting on the
workstation this step exists to survive the loss of — so commit and push
before deleting anything. Confirm what landed without decrypting: the YAML
keys are plaintext, so `grep -oE '^[a-z0-9_]+:' threkir/push-credentials.sops.yaml`
lists them and prints no value.

Only then delete the `.p8` files, because a private key in a sync-happy folder
is the thing the estate repo exists to avoid. A *new* file in the estate needs
a `creation_rules` entry in its `.sops.yaml` first or `sops` refuses to
encrypt it (fail-closed by design); this one already has its rule. From the
project repo the same path fails with *"config file not found, or has no
creation rules"*, which reads like a missing rule rather than a missing `cd`.

## 9. Supabase Apple provider

**Authentication** → **Providers** (or Sign In / Providers) → **Apple** →
enable.

| Field | Value |
|---|---|
| Client IDs | `com.threkir.web` **first**, then `com.threkir.app` |
| Secret Key (for OAuth) | a generated client secret — see below |

Order matters in that list: the Services ID must be first, or the web flow and
the native flow route to the wrong client.

**URL Configuration is already done** — Site URL, the four Redirect URLs and
**Allow manual linking** are project-wide, not per-provider, and the Google
thread set them on 2026-09-21
([`google_provisioning.md` § 7](google_provisioning.md)). Manual linking is the
one to know about: without it **Link Apple** on `/settings/account` fails with
`manual_linking_disabled`, exactly as Link Google would. Nothing to do here
beyond confirming they are still set.

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
([decisions § 1684](../architecture/decisions.md)).

1. Set the repo secret **`PUBLIC_APPLE_AUTH_ENABLED`** to `true`.
2. Publish a **`web@<version>`** GitHub *Release* — `release-web.yml` is
   `on: release`, so a bare tag push deploys nothing ([`releasing.md`](releasing.md)).
3. **Approve the deployment.** The job declares `environment: production`,
   which carries a required-reviewer rule, so the run parks at `waiting` until
   a human clicks *Review deployments → Approve and deploy*. A re-run resets
   the gate and needs approving again.

The secret and the release are both needed. `release-web.yml` writes
`apps/web/.env` from its own `env:` block and the build reads nothing else, so
the secret alone changes nothing — which is exactly how eight flags sat
permanently off until [§ 1683](../architecture/decisions.md).

This is the same three steps Google's
[step 8](google_provisioning.md) takes, and `web@1.8.0` walked them on
2026-09-21: afterwards
`curl -sS https://threkir.com/_app/env.js | grep -o 'PUBLIC_[A-Z_]*:"[^"]*"'`
prints the gate set that deploy actually shipped, which beats reading the
button.

## 12. Android release for push

Publish a **`mobile_android@<version>`** Release — `release-android.yml` is
`on: release` and declares `environment: production` too, so this is a Release
plus an approval, not a tag. The `google-services` Gradle apply is
conditional and `release-android.yml` only **warns** when the config secret is
absent, so any AAB built before 2026-09-18 registers no device token at all —
and a client that never registers is indistinguishable from a broken sender.

## 13. Android's Apple dart-defines

Set two `production` environment secrets, then cut the step-12 Release; they
ride the same build:

- **`MOBILE_APPLE_SERVICE_CLIENT_ID`** → the dart-define `APPLE_SERVICE_CLIENT_ID`
- **`MOBILE_APPLE_REDIRECT_URI`** → the dart-define `APPLE_REDIRECT_URI`

**Both or neither** — `appleSignInAvailable()` requires the pair, so one alone
leaves the button exactly as it was.

Until [§ 1696](../architecture/decisions.md) this step was not a secret at all.
Neither name reached a release build by any route: `main.dart`'s bridge did not
carry them, so they were debug-only in the [§ 709](../architecture/decisions.md)
sense, and `release-android.yml` did not pass them either. Both halves are
wired now, which is why this reads as two secrets rather than as a code change.

`appleSignInAvailable()` in
[`apple_auth.dart`](../../apps/mobile_android/lib/apple_auth.dart) gates the
Android button on two dart-defines, the way Google's is gated on
`GOOGLE_WEB_CLIENT_ID`:

- `APPLE_SERVICE_CLIENT_ID` — the **same Services ID** from step 5, `com.threkir.web`
- `APPLE_REDIRECT_URI` — the **same return URL** from step 5,
  `https://mcbgrgvegqcmdmtraikl.supabase.co/auth/v1/callback`. It has to be one
  of the Return URLs registered there or Apple rejects the authorization.

iOS needs neither, and **iOS is not gated at all** — `appleSignInAvailable()`
opens with `if (defaultTargetPlatform == TargetPlatform.iOS) return true`, and
`Runner.entitlements` already declares `com.apple.developer.applesignin`. The
only Apple-side thing the native flow waits on is step 3's capability. (Docs
elsewhere refer to an `apps/mobile_ios` constant `_kAppleSignInEnabled` as the
iOS gate; no such symbol exists anywhere in the tree.)

## 14. Apple Distribution certificate

On the Mac. **Keychain Access** → menu **Keychain Access** → **Certificate
Assistant** → **Request a Certificate From a Certificate Authority** → your
Apple Account email, common name `Threkir Distribution`, **Saved to disk**.

developer.apple.com → **Certificates** → **(+)** → **Apple Distribution** →
upload that `.certSigningRequest` → **Download** → double-click the `.cer` to
install it. Pick **Apple Distribution**, not the older *iOS Distribution*:
`release-ios.yml` looks for an identity named `Apple Distribution: …` and fails
naming the certificate if it finds none.

Back in Keychain Access → **My Certificates** → expand the new certificate and
confirm a private key sits under it (no key means the CSR was made on another
Mac, and the certificate cannot sign anything) → select the certificate →
**File** → **Export Items…** → `threkir-distribution.p12`, with a strong
password. Then, from the `threkir` checkout:

```
base64 -i ~/Desktop/threkir-distribution.p12 | gh secret set IOS_BUILD_CERTIFICATE_BASE64 --env production
```

```
gh secret set IOS_P12_PASSWORD --env production
```

The second prompts for the value, so it never reaches shell history. Back the
`.p12` and its password up the way step 8 does (`ios_distribution_p12_base64`,
`ios_p12_password`), then delete the file. It expires after a year; a lost or
expired one is replaced by making a new one — Apple allows two at once — and
re-running this step.

## 15. App Store provisioning profiles — one per bundle

**Profiles** → **(+)** → under Distribution, **App Store Connect** → App ID
`com.threkir.app` → the certificate from step 14 → name `Threkir App Store` →
**Generate** → **Download**. Again for `com.threkir.app.watchapp`, named
`Threkir Watch App Store`.

**Make these after steps 3 and 4 are finished, App Group assignment
included.** A profile records the App ID's capabilities when it is generated,
so a capability enabled afterwards is missing from it until it is regenerated —
and the build fails on the entitlement the profile lacks.

```
base64 -i ~/Downloads/Threkir_App_Store.mobileprovision | gh secret set IOS_PROVISIONING_PROFILE_BASE64 --env production
```

```
base64 -i ~/Downloads/Threkir_Watch_App_Store.mobileprovision | gh secret set IOS_WATCH_PROVISIONING_PROFILE_BASE64 --env production
```

Profiles are not secret and can be regenerated at any time, so they need no
backup. Nothing else is configured: the workflow reads each profile's bundle id
and the team id out of the profile itself (decisions § 1701), and fails naming
the bundle if either profile is missing, is a development or ad hoc one, or is
for the wrong App ID.

## 16. App Store Connect API key

This is what uploads to TestFlight without an Apple Account password.
**appstoreconnect.apple.com** → **Users and Access** → **Integrations** →
**App Store Connect API** → **Team Keys** (the first time, the Account Holder
has to **Request Access** and accept) → **(+)** → name `GitHub Actions`, access
**App Manager** → **Generate** → **Download API Key**. It downloads **once**.
Note the **Key ID** on the row and the **Issuer ID** above the table.

```
gh secret set APP_STORE_CONNECT_API_PRIVATE_KEY --env production < ~/Downloads/AuthKey_<key id>.p8
```

```
gh secret set APP_STORE_CONNECT_API_KEY_ID --env production --body <key id>
```

```
gh secret set APP_STORE_CONNECT_API_ISSUER_ID --env production --body <issuer id>
```

The `.p8` goes in **as it is, not base64**: the upload action reads PKCS#8
text. Back it up as `asc_api_key_p8` with its Key ID the way step 8 does, then
delete the download.

## 17. App Store Connect app record

**Apps** → **(+)** → **New App** → platform **iOS**, name `Threkir`, primary
language, bundle ID `com.threkir.app` (the dropdown lists step 3), SKU
`threkir-ios`, **Full Access**. The Apple Watch app needs no record of its own;
it ships inside this one. The listing itself — screenshots, privacy label, age
rating, review notes — is the checklist in
[`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md#production-readiness-checklist).

To sell Pro on iOS: sign the Paid Apps agreement (**Business**), create the
subscription product, connect the app in RevenueCat, and set RevenueCat's Apple
key as `MOBILE_REVENUECAT_API_KEY_IOS`. Without that key the build shows Pro as
coming soon, because iOS may not fall back to the web checkout
([decisions § 1700](../architecture/decisions.md)).

## 18. First release to TestFlight

```
gh release create mobile_ios@1.0.0 --title "iOS 1.0.0" --generate-notes
```

Approve the `production` environment when the run asks. Its first step names
every secret still unset, so a missing one costs seconds, not a build. The
build lands in TestFlight after Apple's processing (tens of minutes). Install
it on an iPhone paired with an Apple Watch before submitting anything.

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
| `native_push_sent_at` stamped but nothing arrives | Was the pre-§ 1682 defect. If it recurs, read the FCM response body — a 404 prunes the token, a 4xx is logged and dropped. |
| Mail never reaches a `privaterelay` address | Step 10, or the wrong domain registered for it. |
