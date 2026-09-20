---
name: Google provisioning runbook
description: The living operator runbook for Google Sign-In — the OAuth consent screen, the web and Android OAuth clients, the Supabase provider, and the two flags that gate them — with a status ledger that is updated as each step lands.
---

# Google Sign-In provisioning — the living runbook

Google sign-in is **code-complete and fail-closed on every platform**. Nothing
below is a diff; all of it is console work plus two secrets and two tags. The
sibling runbook for the Apple half is
[`apple_provisioning.md`](apple_provisioning.md), and the two share nothing but
the Supabase callback URL — do them in either order.

**This file is the progress ledger.** Update the status table in the same pass
that does the step. The design records are
[`web_app_auth.md`](../features/web_app_auth.md) and
[`apps/mobile_android/local_testing.md`](../../apps/mobile_android/local_testing.md).

## Status

Last moved: **2026-09-20**.

| # | Artifact | Where it ends up | State |
|---|---|---|---|
| — | Google Cloud project `threkir` | — | **Done 2026-09-18** — created as the Firebase project; same project |
| 1 | OAuth consent screen (Google Auth Platform) | GCP console | ☐ |
| 2 | **Web** OAuth client | Supabase provider + `MOBILE_GOOGLE_WEB_CLIENT_ID` | ☐ |
| 3 | Supabase Google provider enabled | Supabase dashboard | ☐ |
| 4 | `PUBLIC_GOOGLE_AUTH_ENABLED` truthy | GitHub repo secret | ☐ |
| 5 | Flag threaded into `release-web.yml` | `main` | **Done 2026-09-20** — #966 |
| 6 | `web@<version>` tag | Release | ☐ — **web sign-in is live here** |
| 7 | **Android** OAuth client (package + SHA-1) | GCP console | ☐ |
| 8 | `google-services.json` refreshed | `GOOGLE_SERVICES_JSON_BASE64` (env `production`) | ☐ |
| 9 | `MOBILE_GOOGLE_WEB_CLIENT_ID` | GitHub env `production` | ☐ |
| 10 | `mobile_android@<version>` tag | Play | ☐ — **Android sign-in is live here** |
| 11 | Consent screen published (out of Testing) | GCP console | ☐ — before real users |

Steps 1–6 are the web thread and 7–10 the Android thread; 7 depends on 2 and
on nothing else in between. The open rows are `☐` rather than `- [ ]` on
purpose, matching the Apple runbook: the survey docs grep `- [ ]`.

## Firebase and Google Cloud are the same project

Every Firebase project **is** a Google Cloud project — one project ID, one
project number, two consoles over it. `threkir` was created from the Firebase
side on 2026-09-18 and is therefore already in Google Cloud; it does not need
creating and must not be created again.

Measured from the shipped `google-services.json`: project `threkir`, number
`79605811581`, Android package `com.threkir.app`, and **zero** `oauth_client`
entries — so no OAuth client of any type exists in it yet.

Open it directly, skipping the project picker, which hides projects behind an
org filter often enough to be worth avoiding:

<https://console.cloud.google.com/apis/credentials?project=threkir>

**`threkir-play` is a different project and is not the one.** It holds the Play
Developer API service account (`PLAY_SERVICE_ACCOUNT_JSON`) — a publishing
credential with no end-user OAuth in it. Both OAuth clients have to live in the
same project as each other, and that project has to be the one the app's
`google-services.json` names, because Google matches an Android caller's
package and signing certificate against clients **in the project that owns the
web client**. Splitting them is the failure that reports itself as
`DEVELOPER_ERROR` with no further detail.

## 1. The OAuth consent screen

In the current console this is **Google Auth Platform** (left nav on the
Credentials page), split into **Branding** and **Audience**. The
**Create credentials → OAuth client ID** button does nothing useful until it
exists, which is where this stalls.

| Field | Value |
|---|---|
| App name | `Threkir` — this is what the account chooser says, so it is user-visible copy |
| User support email | your address |
| Audience | **External** |
| Authorized domain | `threkir.com` |
| Developer contact | your address |

Scopes: leave the defaults. We request `email` and `profile` only — both
non-sensitive, which is what makes step 11 free.

Leave it in **Testing** for now and add your own address under Audience → Test
users. Testing caps you at 100 named users and nobody else can sign in; that is
the right state while the rest of the ledger is open.

## 2. The Web OAuth client

**Credentials → Create credentials → OAuth client ID → Web application.**

| Field | Value |
|---|---|
| Name | `Threkir — Supabase` |
| Authorized JavaScript origins | `https://threkir.com`, `https://www.threkir.com`, `http://localhost:7777` |
| Authorized redirect URIs | `https://mcbgrgvegqcmdmtraikl.supabase.co/auth/v1/callback`, `http://localhost:54321/auth/v1/callback` |

Copy the **Client ID** (`….apps.googleusercontent.com`) and the **Client
secret**. The client ID is not secret — it ships inside every build. The secret
is, and it goes into the Supabase dashboard and nowhere else in this repo.

The two localhost entries are what make a local stack work later; Google
accepts `http://` for localhost specifically, which is the difference from
Apple, where no local variant is possible at all.

**This one client serves both platforms.** Android's native flow sends its ID
token to Supabase with this client as the audience, which is why step 9 feeds
the *web* client ID to the Android build. There is no second web client.

## 3. Supabase Google provider

**Authentication → Sign In / Providers → Google → enable.**

| Field | Value |
|---|---|
| Client IDs | the step-2 **web** client ID |
| Client Secret (for OAuth) | the step-2 secret |

Unlike Apple, the secret here is the literal secret string — there is no JWT to
generate and nothing that expires in six months.

The same **Client IDs** field is what `signInWithIdToken` validates the `aud`
claim of a native Android token against
([`api_client.dart:418`](../../packages/api_client/lib/src/api_client.dart)), so
one entry covers the web redirect flow and the Android native flow both.

## 4. The repo secret

Set the **repository** secret `PUBLIC_GOOGLE_AUTH_ENABLED` to `true`.

Repository, not the `production` environment. `release-web.yml`'s single job
binds `production` for a `web@` tag and **`preview` for everything else**, so an
environment-scoped secret would reach the tagged prod build and leave every
preview deploy with the button greyed out — a difference between the two sites
that looks like a broken preview. A repo secret reaches both legs.
(`release-android.yml` has no such split: it declares `environment: production`
flatly, which is why step 9 goes there instead.)

The flag itself is
[`google_auth_flag.ts`](../../apps/web/src/lib/core/google_auth_flag.ts) and it
is fail-closed: unset, empty, `false` and `0` all mean off, and the button keeps
its label behind a "Soon" pill.

## 5. The flag threading — done

**Done 2026-09-20**, in [#966](https://github.com/Absence0760/threkir/pull/966).
Recorded because it was a prerequisite nobody could see: `release-web.yml`
writes `apps/web/.env` from its own `env:` block and the build reads nothing
else, so while `main` carried zero occurrences of `PUBLIC_GOOGLE_AUTH_ENABLED`
the step-4 secret was inert however it was set — the
[§ 1683](../architecture/decisions.md) failure, which
`ci_workflow_guards.test.ts` now derives from the `*_flag.ts` modules to stop
happening silently.

Verify before blaming step 4 if the button stays grey:
`git show origin/main:.github/workflows/release-web.yml | grep -c PUBLIC_GOOGLE_AUTH_ENABLED`
must print **2** — the mapping and the heredoc both.

## 6. Tag the web release

Cut **`web@<version>`**. Google sign-in is live on the web at this point; stop
here if the phone can wait.

## 7. The Android OAuth client

**Credentials → Create credentials → OAuth client ID → Android.**

| Field | Value |
|---|---|
| Package name | `com.threkir.app` |
| SHA-1 certificate fingerprint | see below |

No client ID is recorded anywhere for this one — it is matched by package plus
signature alone, which is why a mismatch has no error message worth reading.

**Which certificate is the whole question.** With Play App Signing enabled,
Google re-signs the app and the fingerprint that reaches the sign-in check is
Play's **app signing** certificate, not the upload keystore's. Read it from
**Play Console → your app → Test and release → Setup → App integrity → App
signing key certificate**. Registering the upload keystore's SHA-1 instead is
the single most common cause of a `DEVELOPER_ERROR` on a release build that
works fine in debug.

For a debug build on the same device, add a second Android client with the
debug keystore's SHA-1:

```
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

## 8. Refresh `google-services.json`

Adding a fingerprint changes the file. Re-download it from **Firebase console →
Project settings → your Android app**, then update the **environment
`production`** secret `GOOGLE_SERVICES_JSON_BASE64` with `base64 -w0` of the new
file.

This is not what `google_sign_in` 7.x reads the client from — it takes
`serverClientId` from step 9's dart-define — but the file is the record of which
fingerprints the project knows about, and a stale one is indistinguishable from
a missing client the next time somebody debugs this.

## 9. The Android dart-define

Set the **environment `production`** secret `MOBILE_GOOGLE_WEB_CLIENT_ID` to the
step-2 **web** client ID — not an Android client ID, which does not exist as a
value to copy.

`release-android.yml:215` maps it to the `GOOGLE_WEB_CLIENT_ID` dart-define, and
`sign_in_screen.dart:179` gates the whole button on that string being non-empty:
an unconfigured build shows `googleSignInSoon` on tap rather than a raw
configuration error.

## 10. Tag the Android release

Cut **`mobile_android@<version>`**. Google sign-in is live on Android.

## 11. Publish the consent screen

**Google Auth Platform → Audience → Publish app.** Until this, only the test
users named in step 1 can sign in — everyone else gets "access blocked", which
reads like a defect in the app.

Because the app requests only `email` and `profile`, publishing is immediate:
no Google verification review, no waiting, no demo video. That is only true
while the scope list stays non-sensitive — adding any Drive/Calendar/Gmail scope
later turns this step into a multi-week review.

## Verifying each thread

**Web**, after step 6:

1. `https://threkir.com/login` — the Google button has no "Soon" pill.
2. Click it. Google's account chooser appears (not an error toast).
3. Pick the account. You land back on `/auth/callback` and then the age/terms
   gate on a first-ever sign-in, `/dashboard` after.
4. Supabase → Authentication → Users shows the row with a `google` identity.

**Android**, after step 10: install the tagged build, Sign In → Sign in with
Google, the system chooser appears and the screen closes signed in. An emulator
needs a **Google Play** system image — the stock AOSP one has no Play services
and fails before any chooser.

## When it breaks

| Symptom | Cause |
|---|---|
| Button still says "Soon" on web | Step 4 or 5 — the secret is unset, or the tag predates the threading |
| `redirect_uri_mismatch` | Step 2 — the URI must match the Supabase callback character for character, including `https://` and no trailing slash |
| "Access blocked: app not verified" | Step 11 — consent screen still in Testing and this account is not a test user |
| `DEVELOPER_ERROR` on Android | Step 7 — wrong SHA-1 (usually the upload key instead of Play's app signing key), or the two clients are in different projects |
| "did not return an ID token" | Step 9 — `MOBILE_GOOGLE_WEB_CLIENT_ID` does not match the client ID in Supabase's Client IDs field |
| Web works, Android does not | Step 3 — the web client ID is in **Client Secret** but missing from **Client IDs**, which the native `aud` check reads |
