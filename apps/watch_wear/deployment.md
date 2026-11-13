# Wear OS deployment plan

How `apps/watch_wear/` (native Kotlin + Compose-for-Wear) ships to the Google Play Store.

Operational counterpart of [`apps/watch_wear/CLAUDE.md`](CLAUDE.md) and [`apps/watch_wear/local_testing.md`](local_testing.md). For tag-driven release mechanics see [`docs/ops/releasing.md`](../../docs/ops/releasing.md). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md).

**Status: plan.** App compiles and runs on emulator + real watches. It ships as the **Wear OS form factor of the phone app's Play listing** (`com.threkir.app`); the form factor is added in Play Console (2026-11-13, #1378) and no Wear bundle has been released yet.

---

## Why the phone app's Play listing

Wear OS apps **are** Android apps — the manifest declares `<uses-feature android:name="android.hardware.type.watch" />` and the Play Store routes installs to paired watches. They can ship in three ways:

1. **Embedded inside the phone app's APK** — the Wear 1.x model, which Wear OS 2 and later do not install from.
2. **A Wear OS form factor of the phone app's listing** — the watch bundle shares the phone's `applicationId` and listing, and is uploaded to its own Wear OS tracks.
3. **A separate listing** — a different `applicationId`, discoverable only on its own.

We ship **#2** ([decisions.md § 2480](../../docs/architecture/decisions.md), amending the listing choice in [§ 15](../../docs/architecture/decisions.md#15-watch_wear-is-pure-kotlin--compose-for-wear-not-flutter)). It used to be #3, as `com.threkir.watchwear`; that listing was a draft that never published, so nobody installed it and nothing migrates. The reasons:

- **Production access.** Play requires a new personal-account app to run a closed test with 12 testers for 14 days before it can reach production. The phone app has had production access since 2026-11-11; a Wear form factor of it asks for a release to a testing track, not a fresh 12-tester test (what Play Console showed on 2026-11-13; that the opt-in then reaches production without one is still to be confirmed once it unlocks).
- **The Data Layer needs it.** The phone hands the watch its Supabase session, starred routes and today's workout over the Wearable Data Layer, and Google Play services only connects the two installs when the package name **and** the signing certificate match across the devices ([Data Layer overview § Security](https://developer.android.com/training/wearables/data/overview)). Under `com.threkir.watchwear` a Play install of each could never have paired.
- **Google recommends it**: the [Wear OS packaging guide](https://developer.android.com/training/wearables/packaging) asks for the same package name as the mobile app and the same listing, which also puts the phone app's ratings on the watch app.

What did not change: the watch app is still native Kotlin and a separate bundle (the phone APK carries no Kotlin watch code), it still installs on its own from the watch's Play Store with no phone app (`com.google.android.wearable.standalone`), and it still releases on its own cadence under its own `watch_wear@*` tags. Crash and ANR metrics stay separable by version code, since the watch's codes are a range of their own (§ Version codes).

---

## Provider — Google Play Console (Wear OS form factor of `com.threkir.app`)

Same developer account and same app as `mobile_android` (`apps/mobile_android/deployment.md`). The Wear-specific parts:

- **Application ID:** `com.threkir.app`, the phone's. It must match `applicationId` in `android/app/build.gradle.kts` and `--package` in `release-watch-wear.yml`. The Kotlin `namespace` (`com.runapp.watchwear`) is a separate setting that only names the source packages; Play never sees it.
- **Form factor:** Play Console → Threkir → Test and release → Advanced settings → **Form factors** → Wear OS (added 2026-11-13). This creates the Wear OS tracks, named `wear:<track>` in the Android Publisher API ([APKs and Tracks](https://developers.google.com/android-publisher/tracks), [edits.tracks](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks)).
- **Three gates, in order** before Wear OS goes live: Wear OS screenshots on every store listing, a Wear bundle released to a testing track, then the opt-in to Wear OS and its review policy. The first two are what this repo supplies.
- **Service account:** the phone's `PLAY_SERVICE_ACCOUNT_JSON`, which already holds "Release apps to testing tracks" on `com.threkir.app`. Nothing to grant.

### Version codes

One app has one version-code space across every track and form factor, and Play refuses a code any track has used ([packaging § Unique version code](https://developer.android.com/training/wearables/packaging)). The phone's code is `git rev-list --count HEAD`, so a watch build of the same commit would collide. `release-watch-wear.yml` adds `WEAR_VERSION_CODE_OFFSET` = **1,000,000,000** to the same count: the phone would need a billion commits to reach the watch's floor, and the watch has 1.1 billion before Play's 2,100,000,000 ceiling. Never lower the offset; codes only go up. `scripts/play_release.test.mjs` pins it.

### Wear OS store screenshots

Play wants 1:1, at least 384x384, app UI only: no watch frame, no added text, no transparency and no circular mask. They are generated from the real screens, not captured by hand:

```bash
heavy bash assets/store/wear/gen-wear-screenshots.sh
```

`WearStoreScreenshotTest` (`app/src/test/.../ui/store/`) renders pre-run, running, a workout step and post-run under Robolectric on a large round Wear device (227 dp at xhdpi, 454x454) with a made-up route, a pinned clock and map tiles off, and the script flattens each onto opaque black into `assets/store/wear/en-US/`. Two runs are byte-identical. Upload them to Store presence → Store listings → default listing → **Wear OS** screenshots. The map draws without tiles (route and track on the night background), which is also what a watch with no MapTiler key shows.

### Wear OS-specific store metadata

Play Console → the Wear OS form factor's settings:

- **Wear OS standalone**: Yes — the app can run without the phone (post-pairing setup).
- **Wear OS quality**: the opt-in reviews the bundle against Google's Wear OS app quality guidelines, separately from the phone's review.

---

## Signing setup

**The phone app's upload key.** One package has one app signing key (held by Google, Play App Signing) and one upload key, so the watch bundle is signed with the phone's upload keystore from the same `ANDROID_KEYSTORE_*` secrets `release-android.yml` reads. Its backup and recovery are the phone's: `apps/mobile_android/deployment.md` § Signing setup.

The Wear-only upload keystore generated on 2026-10-06 for `com.threkir.watchwear` is retired with that listing. Removing its `WATCH_WEAR_KEYSTORE_*` / `WATCH_WEAR_KEY_*` secrets from the `production` environment, and its sops copy at `../infra-secrets/threkir/wear-upload-keystore.sops.yaml`, are owner steps on #1378.

### GitHub Secrets required

All on the `production` environment, which the job names:

| Secret | Source |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | shared with `release-android.yml` |
| `ANDROID_KEYSTORE_PASSWORD` | shared |
| `ANDROID_KEY_ALIAS` | shared |
| `ANDROID_KEY_PASSWORD` | shared |
| `PLAY_SERVICE_ACCOUNT_JSON` | shared |
| `WATCH_WEAR_SENTRY_DSN` | optional, the watch's own Sentry project |

Plus build-time secrets injected via Gradle properties:

| Secret | Source |
|---|---|
| `SUPABASE_URL` | the raw `https://<ref>.supabase.co` — same value as `PUBLIC_SUPABASE_URL` (`api.threkir.com` only if the Pro-only custom domain is ever provisioned) |
| `SUPABASE_ANON_KEY` | publishable key |
| `PUBLIC_MAPTILER_KEY` | shared MapTiler key |

These are passed to Gradle via `-PSUPABASE_URL=...` and end up in `BuildConfig` constants the Kotlin code reads.

---

## Build configuration

### `applicationId`

`apps/watch_wear/android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        applicationId = "com.threkir.app"   // the phone's package
        minSdk = 30           // Wear OS 3+
        targetSdk = 35
        compileSdk = 37
        versionCode = ...     // 1,000,000,000 + git rev-list --count HEAD
        versionName = ...     // derived from the tag
    }
}
```

### Build flavours

Same shape as the phone app: `dev` and `production`. The dev flavour reads from `apps/watch_wear/android/.env.local` (gitignored, has `BYPASS_LOGIN=true` for local testing). The production build reads only from Gradle properties (no `.env.local` on the CI runner).

### Manifest declarations to verify before launch

`apps/watch_wear/android/app/src/main/AndroidManifest.xml`:

- `<uses-feature android:name="android.hardware.type.watch" />` — REQUIRED, makes the app eligible for Wear listing
- `android.permission.ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` — both are requested together (Android 12+ ignores a fine request without coarse), and a runner who grants Approximate only is stopped at a Precise-location notice before the run starts. `ACCESS_BACKGROUND_LOCATION` is **not** declared and never has been; this list used to claim it (`decisions.md § 1020`). Do not disclose it.
- `android.permission.ACTIVITY_RECOGNITION`
- `android.permission.BODY_SENSORS` — Health Services HR via `MeasureClient`
- `android.permission.BODY_SENSORS_BACKGROUND` — **removed, do not re-add without changing the client.** It gates `PassiveMonitoringClient`; `HeartRateMonitor` uses `MeasureClient`, whose documented background access is no. It was declared and never requested, so it was inert as well as inapplicable (`decisions.md § 1015`). `ManifestGuardsTest` fails if it comes back.
- `android.permission.FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`
- `android.permission.FOREGROUND_SERVICE_HEALTH` — `RunRecordingService` reads HR via Health Services while recording. Both the manifest (`foregroundServiceType="location|health"`) and the runtime `startForeground` mask must carry `health`, and it is the runtime mask the platform enforces from API 34 (`decisions.md § 1016`); the type is passed only once `BODY_SENSORS` or `ACTIVITY_RECOGNITION` has been granted, which is the platform's prerequisite for it.
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — for the long-run battery whitelist UX
- `android.permission.WAKE_LOCK` — partial wake-lock during recording
- `<service android:name=".tiles.ActiveRunTileService">` with `BIND_TILE_PROVIDER` permission ([`apps/watch_wear/CLAUDE.md` § Active-run tile](CLAUDE.md))

The `meta-data` for `com.google.android.wearable.standalone` should be `true` — declares we work without a paired phone.

---

## Release workflow — `watch_wear@*`

Triggered by publishing a GitHub Release tagged `watch_wear@1.2.3`. The workflow at `.github/workflows/release-watch-wear.yml`:

1. Checks out the tag.
2. Reads the version name from the tag; the version code is `WEAR_VERSION_CODE_OFFSET` plus the commit count (§ Version codes).
3. Sets up JDK 21 (matches the Android Studio JBR pin).
4. Decodes the phone's `ANDROID_KEYSTORE_BASE64` and checks the password and alias with `keytool` before the build.
5. `./gradlew bundleRelease -PSUPABASE_URL=$SUPABASE_URL ...` in `apps/watch_wear/android`, signed with that upload key.
6. Attaches the AAB to the GitHub Release, before any Play call, so a failed upload still leaves a signed bundle to hand-upload.
7. `node scripts/play_release.mjs upload --package com.threkir.app --form-factor wear ...` puts it on the **Wear OS internal testing track**: it finds the track in the track list Play returns (`wear:qa`, the name Google's track reference gives, or `wear:internal`), skips the upload when Play already holds the version code, checks the code Play read out of the bundle, and commits with `ERROR_IF_IN_REVIEW`. That last one is why the upload is not `r0adkll/upload-google-play`: its commit takes Play's default, which cancels whatever is in review and resubmits it, and under one package that is the phone's production release. A phone release in review therefore fails this step with the reason; re-run it once that review clears.

Promotion to Wear OS production stays manual in Play Console, after smoke-testing on a real watch (emulator-only does not exercise haptics, the optical HR sensor or tile freshness). The phone's promote / daily-ramp pair (`play_release.mjs promote` / `advance`) only ever touches the `production` track, never `wear:production`.

---

## Observability

| Surface | Tool | What |
|---|---|---|
| Crash reports | Sentry — separate "watch-wear" project under the same org | grouped Kotlin stacks, breadcrumb trail |
| Anomaly detection | Play Console → Statistics → Crashes & ANRs | per-device-model breakdowns |
| Battery usage | Play Console → Android vitals → Battery | excessive wakeups, partial-wake-lock leaks |
| Tile load latency | Play Console → Wear OS → Tile metrics | tile cold-start time, freshness warnings |

Wear OS crash rates are noisier than phone — emulator crashes from the device-model fragmentation can dominate for the first month. Watch real-device crashes specifically (filterable in the Console) and triage those.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Play Console developer fee | one-time, shared with phone app | $0 |
| Sentry watch-wear project | within the same Sentry org's free tier | $0 |
| **Subtotal** | | **$0** |

Marginal cost per install: $0. The watch app doesn't make additional API calls beyond what the phone app already does (sync, route fetch, race-mode pings) — so it doesn't push the Supabase tier.

---

## Rollback

Same Play Store roll-forward model as the phone app — see `apps/mobile_android/deployment.md` § Rollback. "Halt rollout" pauses propagation; tag a higher `versionCode` to fix forward.

A Wear OS-specific rollback consideration: when the phone app + watch app deploy together, a phone-app rollback that doesn't include a corresponding watch-app rollback can leave the two on incompatible payload schemas. The cross-platform fixture test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`) is the protection — both sides must agree on the canonical run-payload shape, and the fixture lives in version control. Rolling back one side without the other only breaks if the rollback crosses a payload-schema bump, which is rare.

---

## Disaster recovery

### Lost upload keystore

It is the phone app's key: `apps/mobile_android/deployment.md` § Disaster recovery applies verbatim.

### Lost Play Console access

Mitigated at the developer-account level (shared with the phone app — `apps/mobile_android/deployment.md` § Disaster recovery applies verbatim).

### Watch app delisting only

A Wear OS-specific edge: Google occasionally tightens Wear OS-specific guidelines and asks for compliance changes (Play Store stricter on tile freshness, complication API deprecations, etc.). These typically come with a 90-day window. Watch the Play Console messages, ship a compliance update before the window closes.

---

## Production readiness checklist

- [x] Wear OS form factor added to `com.threkir.app` in Play Console (2026-11-13, #1378)
- [ ] Wear OS standalone meta-data set to `true`
- [ ] Wear OS screenshots (`assets/store/wear/en-US/`) uploaded to every store listing; icon and feature graphic are the phone listing's
- [x] Privacy policy URL and Data safety: the phone listing's, which now covers the watch too. Re-check the Data safety form against the watch's data (heart rate, location) before the opt-in
- [x] Upload key: the phone app's (`ANDROID_KEYSTORE_*`)
- [x] Play service account: the phone app's, which already releases to testing tracks on `com.threkir.app`
- [ ] Opt in to Wear OS and its review policy (unlocks after the screenshots and the first testing-track release)
- [ ] Owner: remove the `WATCH_WEAR_KEYSTORE_*` / `WATCH_WEAR_KEY_*` secrets and the retired Wear keystore's sops copy; delete the draft `com.threkir.watchwear` app after the first Wear release
- [ ] Production Gradle properties verified (Supabase URL, anon key, MapTiler)
- [ ] Manifest reviewed against the permissions list
- [ ] Active-run tile service declared with the right permission
- [ ] First `watch_wear@*` release built clean, AAB landed on the Wear OS internal track (not a phone track)
- [ ] Internal smoke test on real watch (Pixel Watch / Galaxy Watch — emulator-only is not sufficient for haptics, BLE HR, tile freshness)
- [ ] Sentry receiving events — set the `WATCH_WEAR_SENTRY_DSN` secret on the `production` environment; `release-watch-wear.yml` passes it as `-PSENTRY_DSN`, and while it is unset a release build ships with Sentry off. The manifest's `io.sentry.auto-init=false` is what makes an empty DSN safe: without it the SDK's init provider throws and the app dies on launch (`decisions.md § 1763`)
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) Wear OS column reflects shipped state
