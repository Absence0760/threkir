---
name: Google sign-in provisioning runbook
description: The living operator runbook for the Google Cloud side of Google sign-in — consent screen, the three OAuth clients, the Supabase provider and the two build-time gates — with a status ledger that is updated as each step lands.
---

# Google sign-in provisioning — the living runbook

One Google Cloud project feeds one feature here — Google sign-in on web,
Android and iOS — but it is the **same project Firebase created for push**
(`threkir`, [`native_push.md`](../features/native_push.md)), so the Clients
list may already hold entries nobody here made. Read it before creating a
duplicate.

**This file is the progress ledger.** Update the status table in the same pass
that does the step; every other doc points here rather than restating. The
design record is [`web_app_auth.md`](../features/web_app_auth.md). Its Apple
sibling is [`apple_provisioning.md`](apple_provisioning.md), which shares
nothing with this one but the Supabase pages at the end.

## Status

Last moved: **2026-09-20**.

| # | Artifact | Where it ends up | State |
|---|---|---|---|
| — | Google Cloud project `threkir` | — | **Done 2026-09-18** — created for push, reused here |
| 1 | Consent screen (Google Auth Platform) | — | **Done 2026-09-20** — Testing, External, `threkir.com` authorized |
| 2 | **Web** OAuth client | Supabase provider + GitHub `MOBILE_GOOGLE_WEB_CLIENT_ID` | **Done 2026-09-20** |
| 3 | **Android** OAuth client, one per SHA-1 | Google console only — no id to copy | ☐ |
| 4 | **iOS** OAuth client | `Runner/Info.plist` (step 10) | ☐ — defer to step 10, same hands |
| 5 | Web client id + secret backed up | estate `threkir/push-credentials.sops.yaml` | **Done 2026-09-20** — `google_oauth_web_client_id` + `_secret` |
| 6 | Supabase Google provider enabled | Supabase dashboard | ☐ |
| 7 | Site URL, Redirect URLs, manual linking | Supabase dashboard | ☐ |
| 8 | `PUBLIC_GOOGLE_AUTH_ENABLED` truthy + `web@` tag | GitHub secret + release | ☐ |
| 9 | `MOBILE_GOOGLE_WEB_CLIENT_ID` + `mobile_android@` tag | GitHub secret + release | ☐ |
| 10 | iOS `GIDClientID` + reversed-id URL scheme | `Runner/Info.plist` | ☐ — **code, and Mac-only** |

The open rows are `☐` rather than `- [ ]` on purpose, for the reason
[`apple_provisioning.md`](apple_provisioning.md) gives: the survey docs grep
`- [ ]`, and [`followups.md`](../product/followups.md) carries this as one
thread. That file tracks whether the thread is open; this table tracks which
step you are on.

## The console moved, and the old path is half-right

Google's **OAuth consent screen** is now **Google Auth Platform**
(<https://console.cloud.google.com/auth/overview?project=threkir>). There is
exactly one consent configuration per project: **Branding**, **Audience**,
**Clients** and **Data access** are views onto that single object, not things
you create separately. A project that has never configured it shows a **Get
started** wizard — app name, support email, audience, developer contact — and
nothing else; the authorized domain and the test users are added afterwards,
under Branding and Audience.

Walkthroughs that route you through *APIs & Services → Credentials → Create
credentials → OAuth client ID* — including this repo's own, before 2026-09-20 —
describe the client half correctly and the consent half not at all. That path
still creates clients, but `Create client` is inert until the consent
configuration exists, so the documented route dead-ends at a control that looks
broken rather than unreachable.

## 1. Consent screen — done

Recorded for the next project rather than for this one. Get started → app name
`Threkir`, user support email, **External**, developer contact → Create. Then
Branding → Authorized domains → `threkir.com`, and Audience → Test users →
your own address.

Leave **Data access** alone. The default `email` + `profile` scopes are
non-sensitive, which is the whole reason this needs no verification review;
adding one sensitive scope converts the project into a weeks-long audit.

Publishing status stays **Testing**, so only addresses listed under Audience →
Test users can sign in at all. Audience → **Publish app** lifts that, with no
review, and is the last thing to do rather than the first.

## 2. Web client — the one everything else depends on

<https://console.cloud.google.com/auth/clients?project=threkir> → **Create
client** → **Web application**, named `Threkir — Supabase`.

- **Authorized JavaScript origins**: `https://threkir.com` and `http://localhost:7777`
- **Authorized redirect URIs**: `https://mcbgrgvegqcmdmtraikl.supabase.co/auth/v1/callback`
  and `http://localhost:54321/auth/v1/callback`

Copy the **Client ID** and **Client secret**; steps 5 and 6 both want them.

**Google only ever redirects to the Supabase host.** The browser goes `/login`
→ Supabase `/authorize` → Google → Supabase `/callback` → the app, so
`threkir.com/auth/callback` is Supabase's own hop and belongs in step 7's
allow-list, not here. Listing it here too is harmless, which is why
[`apps/web/local_testing.md`](../../apps/web/local_testing.md) says to. The
`localhost:54321` line is the local Supabase stack, so one client covers prod
and local dev.

## 3. Android client — once per signing key, not once per app

**Create client** → **Android**, package name **`com.threkir.app`** (the
`applicationId`, not the `com.example.` Flutter default this repo's docs
carried until 2026-09-20), plus one SHA-1. There is no id and no secret to
copy: Google matches this client on package name + signature at sign-in time.

Google takes one fingerprint per client, so this is one client per key:

- **Debug** (emulator, `flutter run`):
  `keytool -keystore ~/.android/debug.keystore -list -v -alias androiddebugkey -storepass android -keypass android | grep SHA1`
- **Upload keystore** — it lives only in the estate repo, so extract it first:
  `cd ~/github/infra-secrets && AWS_PROFILE=threkir sops --decrypt --extract '["keystore_jks_base64"]' threkir/android-upload-keystore.sops.yaml | base64 -d > /tmp/upload-keystore.jks`
  then `keytool -keystore /tmp/upload-keystore.jks -list -v -alias upload | grep SHA1`
- **Play App Signing** — Play Console → the app → Test and release → Setup →
  App signing → *App signing key certificate*. **This is the fingerprint real
  users carry**, because Play strips the upload signature and re-signs with its
  own key. It does not exist until the first upload, so it is not actionable
  before step 9; skipping it is the classic works-on-my-phone,
  fails-from-the-store failure.

## 4. iOS client

**Create client** → **iOS**, bundle id **`com.threkir.app`**. The id appears in
the Clients list immediately; there is no secret.

**This is the one step worth deferring to step 10**, and the ordering is not
arbitrary: the value the plist needs is the *reversed* form of this client's
id, so creating the client and registering its URL scheme is one unit of work
for whoever has the Mac. Created months early, the id just sits in the estate
file unused and they have to go and read it anyway. Nothing between here and
step 9 depends on it — an iOS build cannot sign in with Google at any point
before step 10 regardless.

Each client's id is its own: the JSON that downloads when you create the **web**
client describes that client alone and will never contain this one.

## 5. Back the credential up

Nothing in this repo reads the Google client secret: Supabase holds the only
operational copy, so there is no Terraform variable and no repo secret for it.
This step is a backup, and a cheap one.

It goes in **`threkir/push-credentials.sops.yaml`**, which despite the name is
the estate's client-credential file — it already carries `apple_team_id` and
`siwa_key_id`, which are Sign in with Apple. Not `prod.sops.yaml`: that one is
the Lambda environment source, read by exact key name (`ANTHROPIC_API_KEY`,
`SENTRY_DSN`, the `OPENAI_*` set, `GRAPHHOPPER_API_KEY`,
`GRAPH_CYCLE_API_KEY`), and anything else there is inert and misfiled.

```
cd ~/github/infra-secrets && AWS_PROFILE=threkir sops threkir/push-credentials.sops.yaml
```

Two keys, matching the file's existing snake_case:

```
google_oauth_web_client_id: <step 2>.apps.googleusercontent.com
google_oauth_web_client_secret: GOCSPX-...
```

A third, `google_oauth_ios_client_id`, joins them whenever step 4 happens.

Delete the downloaded `client_secret_*.json` once both values are in here and
in Supabase. `.gitignore` refuses that filename, so it cannot be committed from
this tree, but the copy in `~/Downloads` is a plaintext secret with no reason
to outlive the paste.

The Android SHA-1 is deliberately **not** stored: it is one `keytool` command
away from a keystore that is already backed up, and a written copy goes stale
the moment a key rotates.

Run `sops` from **inside** the estate repo — config discovery is relative to
the working directory, not to the file being written, and from elsewhere it
fails with *"config file not found, or has no creation rules"*, which reads as
a missing rule rather than a missing `cd`. A **new** filename would genuinely
need a `creation_rules` entry first: the estate `.sops.yaml` matches exact
paths, not `^threkir/.*`.

Unlike the two Apple `.p8` files, this one is not download-once — the console
shows the secret again, and it can be reset. Losing it costs a console trip,
not a rotation.

## 6. Supabase Google provider

<https://supabase.com/dashboard/project/mcbgrgvegqcmdmtraikl/auth/providers> →
**Google** → enable.

- **Client IDs**: the **web** client id. If step 4 has happened, a comma and the
  **iOS** client id after it, no space — otherwise add that when it does
- **Client Secret (for OAuth)**: the step-2 secret

Both ids because the audiences differ by platform. Web and Android both present
a token minted for the **web** client — `initialize(serverClientId:)` in
[`sign_in_screen.dart`](../../apps/mobile_android/lib/screens/sign_in_screen.dart)
is what forces that on Android — while iOS may mint for the iOS client. That
last point is the one thing here no Linux session can settle, and the field
takes a list, so listing both costs nothing and saves a debugging session at a
layer nobody suspects.

## 7. Supabase URL configuration

Same dashboard, **URL Configuration**:

- **Site URL**: `https://threkir.com`
- **Redirect URLs**: `https://threkir.com/auth/callback`,
  `https://threkir.com/auth/reset`, `com.threkir.app://login-callback`,
  `http://localhost:7777/auth/callback`

And on the Providers page, **Allow manual linking** — without it **Link
Google** on `/settings/account` fails with `manual_linking_disabled`.

Steps 6 and 7 are shared with [`apple_provisioning.md`](apple_provisioning.md);
doing them for one provider does most of the work for the other.

## 8. Turn the web button on

The web code is done and fail-closed; there is no diff to write.

1. Set the repo secret **`PUBLIC_GOOGLE_AUTH_ENABLED`** to `true`.
2. Cut a **`web@<version>`** tag.

Both are needed. `release-web.yml` writes `apps/web/.env` from its own `env:`
block and the build reads nothing else, so the secret alone changes nothing —
which is how eight flags sat permanently off until
[§ 1683](../architecture/decisions.md).

## 9. Turn the Android button on

1. Set the repo secret **`MOBILE_GOOGLE_WEB_CLIENT_ID`** to the **web** client
   id from step 2 — not the Android one, which has no id at all.
2. Tag **`mobile_android@<version>`**.

`sign_in_screen.dart` reads the value through `dotenv` and shows the
`googleSignInSoon` notice while it is empty, so a build made before the secret
landed is indistinguishable from a broken credential.

## 10. What iOS still owes — code, not credential

[`apps/mobile_ios/ios/Runner/Info.plist`](../../apps/mobile_ios/ios/Runner/Info.plist)
declares one URL scheme, `com.threkir.app` for the Supabase auth deep link, and
no `GIDClientID`. `google_sign_in` 7.x on iOS needs an iOS client id — from
`GIDClientID`, or from the `GoogleService-Info.plist` push provisioning already
puts in the Runner target — **and** that client's reversed id registered as a
URL scheme for the redirect back into the app. Until the scheme is added, iOS
Google sign-in throws at `initialize()` however correct everything above is.

Android and web are unaffected, and no Linux session can verify the fix, which
is why this is a ledger row rather than a diff.

## Local dev

Optional, and independent of everything above except step 2.

1. `apps/backend/supabase/config.toml` → `[auth.external.google]` →
   `enabled = true` plus `client_id` / `secret`, then
   `cd apps/backend && supabase stop && supabase start`
2. `apps/mobile_android/.env.local` → `GOOGLE_WEB_CLIENT_ID=<web client id>`
3. `apps/web/.env.development` already carries `PUBLIC_GOOGLE_AUTH_ENABLED=true`

Test paths for the sign-up, link and unlink flows are in
[`apps/web/local_testing.md`](../../apps/web/local_testing.md) and
[`apps/mobile_android/local_testing.md`](../../apps/mobile_android/local_testing.md).

## Verifying, in the order the signal appears

1. `/login` shows **Continue with Google** with no "Soon" pill. Still pilled →
   step 8's secret did not reach a build. That is a release, not a Supabase
   setting.
2. The button reaches Google's account chooser. A `redirect_uri_mismatch` here
   names the URI Google was asked for — it will be the Supabase callback, and
   it is missing from step 2.
3. The return lands on `/auth/confirm-age` (first sign-in) or `/dashboard`, and
   a user appears in Supabase → Authentication → Users. Bounced to `/login`
   with no session → step 7, not step 2.
4. Android: the system chooser opens and sign-in completes.
5. `/settings/account` → **Link Google** on an email account → two rows under
   Sign-in Methods sharing one `user_id`.

Remember the app is in **Testing** until you publish it, so every one of these
must be run as an address listed under Audience → Test users.

## When it breaks

| Symptom | Cause |
|---|---|
| `Create client` greyed out | No consent configuration yet — run the Get started wizard (step 1). |
| `redirect_uri_mismatch` | The Supabase callback is not in step 2's redirect list. The error text names the URI it wanted. |
| Returns to `/login` with no session | Step 7's Redirect URLs, not Google. A target that is not on the list falls back to the Site URL. |
| "Google sign-in did not return an ID token" on Android | The Android client's package name or SHA-1 does not match the installed build. Play-signed builds need Play's fingerprint, not the upload key's. |
| Nothing at all happens on Android | Emulator without Google Play services — use a Google Play system image. |
| Works for you, fails for everyone from the Play store | The Play App Signing SHA-1 in step 3 was never registered. |
| iOS throws at `initialize()` | Step 10. No credential fixes this. |
| A nonce error on a native sign-in | Supabase's **Skip nonce check** toggle on the Google provider page. Leave it off unless you hit this. |
| `access_denied` for a colleague | Still in Testing — add them under Audience → Test users, or publish. |
