# Mobile iOS deployment plan

How `apps/mobile_ios/` ships to the Apple App Store, including the bundled `apps/watch_ios/` Apple Watch target.

Operational counterpart of [`apps/mobile_ios/CLAUDE.md`](CLAUDE.md) and the byte-identical-twin convention with `apps/mobile_android/` ([decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md). For tag-driven release mechanics see [`docs/ops/releasing.md`](../../docs/ops/releasing.md).

**Status: release path built, not yet run** (2026-09-21, [decisions § 1701](../../docs/architecture/decisions.md)). Publishing a `mobile_ios@*` Release signs the phone app and the watch app it embeds and uploads them to TestFlight. What remains is operator provisioning — [`docs/ops/apple_provisioning.md`](../../docs/ops/apple_provisioning.md) steps 2–4 and 14–18 — and the first device run on TestFlight.

---

## What this doc covers

The iOS app and the Apple Watch app are **one deployment**. The watch app is a target of `Runner.xcodeproj` and is copied into the iOS app's `.ipa` by an Embed Watch Content phase, so there's no separate listing, no separate review, no separate upload. The Swift sources live under `apps/watch_ios/` and are **referenced** from the phone project rather than copied — one copy on disk, two targets. `apps/watch_ios/WatchApp.xcodeproj` also stays, as the test host the `test-watch-ios` CI job builds; claim (15) of `scripts/check_watch_ios_source.mjs` fails a PR when the two projects stop describing the same app. See [decisions § 1679](../../docs/architecture/decisions.md).

So: `mobile_ios@1.2.3` triggers one CI workflow that ships **both** apps.

---

## Provider — Apple App Store Connect

**Distribution:** App Store + TestFlight. **There is no third option** — Ad Hoc caps at 100 pre-registered devices, the Enterprise program is for an organisation's own employees, and the EU's DMA Web Distribution route requires an EU-established entity with over a million first annual EU installs behind it. The website links to the App Store; it never serves an `.ipa`. See [decisions.md § 379](../../docs/architecture/decisions.md).

**TestFlight first.** Internal testers (up to 100 Apple IDs in the developer team) and external testers (up to 10,000 via a public TestFlight link) can install before the App Store rollout. Treat TestFlight as the equivalent of Play's Internal track.

**Bundle IDs:**

```
com.threkir.app                       ← iOS phone app
com.threkir.app.ShareExtension        ← share extension the phone app embeds (route files from the share sheet)
com.threkir.app.RunActivity           ← Live Activity widget extension the phone app embeds
com.threkir.app.watchapp              ← Apple Watch app target
com.threkir.app.watchapp.complication ← watch complication (WidgetKit extension the watch app embeds)
```

**Country / region rollout:** Same shape as Android — start with UK + Australia + US, expand once stable.

---

## One-time Apple Developer Program setup

1. **Pay $99/year for the Apple Developer Program.** Use a long-lived team mailbox, not a personal Apple ID. Apple's account recovery is brutal — it's worth the extra ~5 minutes of setup to use a shared account.

   **Creating that Apple Account — the parts that are irreversible or that fail enrollment.** The mailbox is the role identity; **the person is not.** First and last name must be the account holder's *legal* name, because Apple verifies it against the enrollment and a company name in those fields delays or fails it — and on an Individual enrollment that legal name becomes the public App Store seller name. Country/Region must match the billing address of the card paying the $99: it sets storefront, currency and tax treatment, and changing it later needs a zero balance and breaks anything subscribed. Birthday must be real and 18+ (the Program requires legal age of majority). The address has to be **receiving mail before you submit** — Apple verifies it with a code in the form itself.
   **With no Apple hardware in the estate, the trusted phone number is the only 2FA channel there is** (codes otherwise go to a signed-in Apple device). So: a number that will still be yours in three years, not VoIP, recorded beside the credentials in Bitwarden, and add a **second** trusted number once the account exists — a lost phone is otherwise a lost developer team. Do **not** set a Recovery Key while there is one operator: it switches Apple's own account-recovery path off, so losing it is permanent, and there is no second admin to recover through.
2. **Individual or Organization — enroll Individual first.** An Organization needs a D-U-N-S number for a **real legal entity** (a DBA or trade name is refused), and its legal name becomes the seller name; an Individual enrollment shows the account holder's legal name there instead — Apple offers individuals **no** alternate-developer-name option at all, and renaming the Apple Account does not change it. The asymmetry is worth knowing before anyone asks why the listing says a person: Apple refuses to *enroll* a DBA or trade name, but an enrolled **organization** may set its displayed developer name to a registered trade name — so a seller line reading `Threkir` needs an entity with a D-U-N-S first, and a registered trade name after it if the entity is not itself called Threkir. None of this touches the app name, which is `Threkir` on either membership. The reason to start Individual anyway is that the upgrade is an **in-place conversion of the same membership** — submit a request as founder/cofounder with the D-U-N-S and any business documents, allow days to weeks for Apple's legal review — so no app is ever transferred between teams. That matters more than it sounds: an app *transfer* requires generating a Sign-in-with-Apple transfer identifier **for every user in the database**, tearing down TestFlight, and passing an app-specific shared secret for the auto-renewable subscriptions. The conversion skips all of it. The direction that is **not** supported is Organization → Individual, which is what makes Individual-first the reversible order. (A later organisation *name* change resets `identifierForVendor`; nothing here reads it — device ids are self-generated UUIDs in `preferences.dart`.) The one real cost of Individual is that the developer portal's certificates, identifiers and keys are Account-Holder-only, so signing cannot be delegated.
2b. **Record these the day enrollment completes, and set the renewal reminder.**
   The **Enrollment ID** Apple hands back on submission is only a support
   reference for a *pending* enrollment — keep it in the Bitwarden item's notes
   until the membership is active, then it stops mattering. What is durable is
   the **Team ID** (10 chars, Membership details — it is what the APNs key is
   uploaded to Firebase alongside, and what Supabase's Apple auth provider
   wants), the Apple
   Account address, and the **expiry date**. None of it is secret; it is account
   metadata, so Bitwarden and the estate file, not a new sops entry.
   The reminder is the part that earns its keep: renewal can only be done by the
   Account Holder, auto-renew is widely reported to fail quietly, and an expired
   membership **pulls every app from the App Store and locks Certificates,
   Identifiers & Profiles** — already-installed copies keep running, but nothing
   ships and no key can be rotated until it is paid. Whether an *existing* APNs
   auth key keeps authenticating through a lapse is undocumented, so do not plan
   to find out. Put a reminder ~3 weeks before expiry against the Apple Account
   address.

3. **Register the App Group first**, at developer.apple.com → Identifiers → **App Groups**: `group.com.threkir.app.activerun`. It is a separate identifier type, so it cannot be ticked on an App ID that does not yet have it registered. The id is **not** `group.com.threkir.app` — the canonical spelling is centralised in [`apps/watch_ios/WatchApp/ActiveRunBridge.swift`](../watch_ios/WatchApp/ActiveRunBridge.swift) and declared in `WatchApp.entitlements`; a mismatch silently shares nothing. Register a **second** group beside it, `group.com.threkir.app.share`, for the share extension's handoff to the phone app — deliberately separate, because the extension clears its container's root on every activation ([`apple_provisioning.md` step 2](../../docs/ops/apple_provisioning.md#then-the-share-extensions-app-group)).
4. **Create the App ID** at developer.apple.com → Identifiers → App IDs → App:
   - Bundle ID: `com.threkir.app` (Explicit)
   - Capabilities: **HealthKit** (leave Clinical Health Records off — we read workouts, not records), **Sign in with Apple** (Configure → *Enable as a primary App ID*), **Push Notifications**, **App Groups** (select **both** groups above — `Runner.entitlements` declares the share group today), and **Associated Domains** only if universal links ship — nothing serves an `apple-app-site-association` today.
   - **Not** Background Modes: it is not a portal capability at all. It lives in `Info.plist`'s `UIBackgroundModes`, already committed and guard-enforced by `scripts/check_ios_native_declarations.mjs` (decisions.md § 742).
   - **Not** Maps: `com.apple.developer.maps` registers a *routing* app that publishes directions coverage. The watch mini-map draws our own polyline through MapKit, which needs no capability.
4b. **Create the Services ID — the web half of Sign in with Apple.** (Field-by-field, with the Supabase and email-relay steps that follow it: [`docs/ops/apple_provisioning.md`](../../docs/ops/apple_provisioning.md).) Identifiers → **Services IDs** → `com.threkir.web`, with the App ID above as its primary. Configure it with the domain `threkir.com` and the return URL `https://<project-ref>.supabase.co/auth/v1/callback` — **Supabase's** callback, not ours, and Apple refuses `http://`, so there is no localhost entry to add. Then Keys → a **second** key with Sign in with Apple enabled, bound to the same primary App ID; its `.p8` is downloadable once and is **not** the APNs key. Those four values (Services ID, Team ID, Key ID, `.p8`) go into Supabase → Authentication → Providers → Apple. This is what unblocks the web Apple button; iOS itself is ungated (`appleSignInAvailable()` returns true there and `Runner.entitlements` already declares `com.apple.developer.applesignin`, so it waits only on step 4a's App ID capability — there is no `_kAppleSignInEnabled` constant in the tree); the ordered version with what to verify afterwards is [`docs/testing/e2e_dev_accounts.md § 2`](../../docs/testing/e2e_dev_accounts.md).
5. **Create the Watch App ID:**
   - Bundle ID: `com.threkir.app.watchapp`
   - Capabilities: **HealthKit**, **App Groups** (the same group — this is the side that actually declares it today; the phone's `Runner.entitlements` does not declare it yet, only the share group, so the bridge's phone half is still owed)
5b. **Create the complication App ID:**
   - Bundle ID: `com.threkir.app.watchapp.complication`
   - Capabilities: **App Groups** only (the same group). The complication is a separate process that draws the snapshot the watch app writes there, so it needs no HealthKit ([`apple_provisioning.md` step 4](../../docs/ops/apple_provisioning.md#then-the-complications-app-id)).
5c. **Create the share extension's App ID:**
   - Bundle ID: `com.threkir.app.ShareExtension`
   - Capabilities: **App Groups** only, assigned to `group.com.threkir.app.share`. A profile without it still signs, and the extension's container lookup then returns nil on device ([`apple_provisioning.md` step 3](../../docs/ops/apple_provisioning.md#then-the-share-extensions-app-id)).
5d. **Create the Live Activity extension's App ID:**
   - Bundle ID: `com.threkir.app.RunActivity`
   - Capabilities: **none**. The extension carries no entitlements; a Live Activity is licensed by `NSSupportsLiveActivities` in the phone app's `Info.plist`, and the card is updated locally, not by push ([`apple_provisioning.md` step 3](../../docs/ops/apple_provisioning.md#then-the-live-activity-extensions-app-id)).
6. **Provisioning profiles.** One App Store Connect distribution profile per bundle ID, made after the App IDs are complete — [`apple_provisioning.md` step 15](../../docs/ops/apple_provisioning.md#15-app-store-provisioning-profiles--one-per-bundle).
7. **Create the App Store listing** at App Store Connect:
   - App information (name, primary category Health & Fitness, content rights)
   - App privacy (next section)
   - Pricing — Free, available worldwide minus the regions we're skipping
   - In-App Purchases — the Pro subscription, connected in RevenueCat ([`apple_provisioning.md` step 17](../../docs/ops/apple_provisioning.md#17-app-store-connect-app-record))

---

## Signing setup

The committed Xcode project signs **automatically**, so a Mac builds and runs on
a device with no setup. The release runner cannot — it has no Apple Account to
sign in with — so `release-ios.yml` hands `scripts/ios_release_signing.mjs` the
App Store profiles, one per signed target, and the script switches the `Release` configuration of
`Runner`, its embedded `ShareExtension` and `RunActivityExtension`, the embedded `WatchApp` and its `WatchAppComplication` to manual signing against the profile
whose bundle id matches, reading the team id out of the profiles. Debug and
Profile are untouched, and nothing is committed back
([decisions § 1701](../../docs/architecture/decisions.md)).

Making the certificate, the profiles and the App Store Connect API key, and
setting them as secrets, is [`apple_provisioning.md` steps 14–16](../../docs/ops/apple_provisioning.md#14-apple-distribution-certificate).
The secret list itself is [`docs/ops/releasing.md` § iOS](../../docs/ops/releasing.md#ios);
the workflow's first step fails in seconds, naming every one that is unset.

---

## Build configuration

### Configurations

One bundle id, `com.threkir.app`, across Xcode's `Debug` / `Profile` /
`Release`; which backend a build talks to comes from its defines, not its
configuration. The app targets **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`):
iPads run it in iPhone compatibility mode, and iPad support can be added in a
later update but never removed once shipped
([decisions § 1701](../../docs/architecture/decisions.md)).

### Production secrets via `dart_defines.json`

The iOS toolchain doesn't accept Supabase's `sb_publishable_...` keys via inline `--dart-define=` — the underscores break Xcode's argument parsing ([decisions.md § 13](../../docs/architecture/decisions.md)). Instead `release-ios.yml` writes a temporary, gitignored `dart_defines.json` from the same secrets the Android release reads — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_KEY`, `WEB_BASE_URL`, `OSRM_URL`, `LIVE_HUB_URL`, `SENTRY_DSN`, `STRAVA_CLIENT_ID`, `APP_RELEASE` — plus `REVENUECAT_API_KEY_IOS`, then builds with `flutter build ipa --release --dart-define-from-file=dart_defines.json` and deletes it. An unset `REVENUECAT_API_KEY_IOS` means Pro is not for sale on iOS: the store SDK is the only way an iOS build may sell it ([decisions § 1700](../../docs/architecture/decisions.md)). `GOOGLE_WEB_CLIENT_ID` is not passed, because iOS offers no Google sign-in (same decision).

The sign-off-gated feature flags (`OFF_ROUTE_ESCALATION_ENABLED`, `ADAPTIVE_FITNESS_GATE`, `WEIGH_IN_GATE`, `ENABLE_NEARBY_RUNNERS`) go in the same file, one key each, once their sign-off lands — `main.dart`'s `String.fromEnvironment` bridge reads them the same way it reads the Supabase keys, and an absent key stays fail-closed. See the table in [`apps/mobile_android/deployment.md`](../mobile_android/deployment.md) for what each one unlocks; the bridge is shared code, so the two platforms accept the same names and the same values ([decisions.md § 709](../../docs/architecture/decisions.md)).

### Info.plist keys to verify before launch

Required strings (Apple rejects without a meaningful description):

- `NSLocationWhenInUseUsageDescription` — "We use your location to record your runs."
- `NSLocationAlwaysAndWhenInUseUsageDescription` — explains why we need background access
- `NSMotionUsageDescription` — pedometer (steps + cadence)
- `NSHealthShareUsageDescription` — HealthKit reads
- `NSHealthUpdateUsageDescription` — HealthKit writes
- `NSBluetoothAlwaysUsageDescription` — BLE chest-strap HR
- `NSPhotoLibraryUsageDescription` — run photos
- `NSPhotoLibraryAddUsageDescription` — saving a shared run card to Photos
- `NSCameraUsageDescription` — taking a photo on the run
- `NSCalendarsWriteOnlyAccessUsageDescription` (iOS 17+) + `NSCalendarsUsageDescription` (the pre-17 fallback) — adding a club event to the calendar. Write-only is the whole ask: the app hands `EKEventEditViewController` a pre-filled event and never reads the calendar (decisions § 692)

Every one of these is translated in `ios/Runner/InfoPlist.xcstrings` (all seven locales, English identical to the plist). A new usage-description key needs its catalog entry before release, or its prompt is English on every non-English phone — `bash apps/mobile_ios/scripts/check_xcstrings_parity.sh` fails until it has one.

Required keys:

- `UIBackgroundModes` array containing `location` (background GPS) and `workout-processing` (Apple Watch session)
- `WKApplication` (in the watch target's Info.plist) — true. This is the
  single-target key; `WKWatchKitApp` is the legacy two-target spelling and
  this project does not use it.
- `WKCompanionAppBundleIdentifier` — `com.threkir.app`. Declared since
  2026-09-18, after the embed it describes actually existed; `WKWatchOnly`
  is gone, the two being mutually exclusive. That was step 3 of the
  five-step sequence in decisions § 1256, and § 1679 records steps 1–4.

### Capabilities to enable in Signing & Capabilities

- HealthKit
- Sign in with Apple
- Push Notifications (APNs) — the `aps-environment` entitlement is already
  committed, resolved from the per-configuration `APS_ENVIRONMENT` build
  setting (`development` on Debug/Profile, `production` on Release). What this
  step adds is the profile that carries the capability; after the first signed
  archive, verify with `codesign -d --entitlements :- <exported>.app` that
  `aps-environment` resolved to `production` rather than to the literal
  `$(APS_ENVIRONMENT)`. The capability is one of three separate things push
  needs on this platform — the other two are the bundled
  `GoogleService-Info.plist` (above) and the worker's APNs `.p8`, and each is
  silent in its own way when missing.
- Background Modes → Location updates + Audio (for TTS) + Background processing.
  **Not** Background fetch: `background_sync.dart` submits a
  `BGProcessingTaskRequest` on iOS, which `processing` authorises and `fetch`
  does not, and claiming a mode the binary never exercises is an App Review
  rejection cause. `scripts/check_ios_native_declarations.mjs` holds the plist
  to that (decisions.md § 742).
- App Groups → `group.com.threkir.app.activerun` (declared by the watch app and its complication; the phone's half of the bridge is still owed) and `group.com.threkir.app.share` (declared by `Runner.entitlements` and `ShareExtension.entitlements` for the share-sheet handoff)

---

## Privacy nutrition label

App Store Connect → App Privacy. Same data classes as the Play Data Safety form, but Apple uses different language:

| Data type | Used to track? | Linked to user? | Purpose |
|---|---|---|---|
| Location (precise + coarse) | No | Yes | App functionality |
| Health & Fitness — heart rate, steps | No | Yes | App functionality |
| Email | No | Yes | App functionality |
| Name (optional display name) | No | Yes | App functionality |
| User ID | No | Yes | App functionality |
| Device ID (APNs/FCM push token) | No | Yes | App functionality |
| Purchase history (subscription state via RevenueCat) | No | Yes | App functionality |
| Photos | No | Yes (when the user uploads) | App functionality |
| Other user content (comments, posts, reviews, notes, Coach chat) | No | Yes | App functionality |
| Crash data, performance data | No | No | App functionality (analytics) |

These rows must stay consistent with `ios/Runner/PrivacyInfo.xcprivacy` (the privacy manifest declares the same collected-data types) and with the Android Data Safety table in [`apps/mobile_android/deployment.md`](../mobile_android/deployment.md).

"Used to track" = correlated with data from other companies for ads. We don't do this; answer "No" everywhere.

Apple cross-checks the App Privacy declarations against actual API usage during review. Declaring "no precise location" while the binary calls `CLLocationManager` requestAlwaysAuthorization is an instant rejection.

### Age rating — capability declarations

App Store Connect's age-rating questionnaire (revised 2025: 4+/9+/13+/16+/18+ tiers) asks about app capabilities, not just content. Declare truthfully:

- **User-generated content / social features** — Yes: social feed, run comments, club posts, direct messages.
- **Location sharing** — Yes: public run/route shares and live spectator links expose (privacy-clipped) location.
- **In-app purchases** — Yes: the Pro subscription (the "In-App Purchases" badge is also derived automatically from the IAP configuration).

The base content rating stays low for a running app; these capability flags are what raise the effective tier, and misdeclaring them is a review rejection. Keep the answers consistent with the Play IARC interactive elements in [`apps/mobile_android/deployment.md`](../mobile_android/deployment.md).

---

## Release workflow — `mobile_ios@*`

Triggered by publishing a GitHub Release tagged `mobile_ios@1.2.3` (a bare tag push does nothing). `.github/workflows/release-ios.yml`, on `macos-latest`, after the `production` environment's approval:

1. Fails in seconds if any required secret is unset, naming each one.
2. Checks out the tag, parses the version (one to three dot-separated integers — the App Store accepts nothing else) and derives the build number from `git rev-list --count HEAD`.
3. Sets up the pinned Flutter SDK, bootstraps the workspace, pins `pubspec.yaml`'s version.
4. Decodes `GoogleService-Info.plist` and checks its bundle id; stubs the bundled `.env.development` asset empty, as Android does.
5. Imports the `.p12` into a keychain whose password is generated for the run, and fails unless it holds an `Apple Distribution` identity.
6. Runs `scripts/ios_release_signing.mjs` against the three profiles (see [Signing setup](#signing-setup)), which also writes `ExportOptions.plist` (`app-store-connect`, manual signing, dSYMs uploaded to Apple).
7. Writes `dart_defines.json`, then `flutter build ipa --release`.
8. Attaches the `.ipa` to the Release **before** uploading, so a refused upload still leaves a signed build to upload by hand.
9. Uploads to TestFlight with the App Store Connect API key, then deletes the keychain and the runtime config.

Lands the build in **TestFlight** (the equivalent of Play's Internal track). Promotion to the App Store is manual in App Store Connect, after a smoke test on an iPhone and a paired Apple Watch.

---

## Apple Watch specifics

### What ships in the IPA

The `WatchApp` target in `Runner.xcodeproj` is built as a dependency of `Runner` and copied to `Runner.app/Watch/WatchApp.app` by the Embed Watch Content phase ([decisions § 1679](../../docs/architecture/decisions.md)); it carries the phone's version and build number through `Flutter/WatchApp.xcconfig`, which App Store Connect requires. It is signed with its own App Store profile. Users who install the iOS app see the Watch app appear in the iOS Watch app's "Available apps" list, where they can install it on their paired watch.

There's no separate review for the Watch app. App Store review covers both targets in one pass, and the listing needs **Apple Watch screenshots** as well as iPhone ones.

### HealthKit entitlements (Watch)

The Watch target needs its own HealthKit entitlement (separate from the iOS one). Set up at developer.apple.com → Identifiers → `com.threkir.app.watchapp` → enable HealthKit.

### Watch Connectivity

The phone-watch transport is `WCSession.transferFile(_:metadata:)` (decisions.md § 40). The phone-side `WatchIngestBridge.swift` is **live**; the queue persists pre-auth payloads to disk via `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` so a phone restart between watch transfer and sign-in doesn't lose the run. No additional setup at deploy time — entitlements travel with the App Group.

### Active-run complication

The `WatchAppComplication` target ([`apps/watch_ios/Complications/README.md`](../watch_ios/Complications/README.md)) is embedded in the watch app and signed with its own profile, `IOS_WATCH_COMPLICATION_PROVISIONING_PROFILE_BASE64`, like every other signed target. A target added to the project needs an App ID, a profile and a secret of its own before the next release; `scripts/ios_release_signing.test.mjs` fails the PR when `release-ios.yml` does not wire one for every signed target, or when [`docs/ops/releasing.md`](../../docs/ops/releasing.md#ios) or [`apple_provisioning.md`](../../docs/ops/apple_provisioning.md) does not name it.

---

## Observability

Same Sentry mobile project as Android — different DSN platform tag, same dashboard. Apple-specific surfaces:

| What | Where |
|---|---|
| Crash reports | Sentry mobile project + Xcode Organizer (post-launch) |
| Energy / power metrics | Xcode Organizer → Energy / Hangs |
| Adoption rate | App Store Connect → Analytics |
| User reviews | App Store Connect → Ratings and Reviews |

**Symbols.** The export uploads dSYMs to Apple (`uploadSymbols`), so Xcode Organizer's crash reports are symbolicated. Sentry is not sent dSYMs: Dart exceptions arrive readable anyway (the build is not obfuscated), but a native Swift / Objective-C crash reaches Sentry as raw addresses until a dSYM upload step is added to `release-ios.yml` — the same state as Android's native symbols.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Apple Developer Program | $99/year | $8.25 |
| Sentry mobile | shared with Android | $0 (covered already) |
| App Store ranking promotions | optional, not planned | $0 |
| **Subtotal** | | **~$8** |

Marginal cost per install: $0. Apple takes 15–30% of in-app purchase revenue (handled via RevenueCat); not directly an "Apple charge" but factor into pricing.

---

## Rollback

App Store has a similar "halt rollout" called **Phased Release** + **Stop Phased Release**:

- New releases ship via Phased Release by default — 1% of auto-update users on day 1, ramping to 100% over 7 days.
- If a regression surfaces during phasing, **Stop Phased Release** in App Store Connect freezes new auto-updates at the current %. Existing installs keep their version.
- Tag a fix as `mobile_ios@1.2.4` and submit. Expedited reviews are available for emergencies but should be reserved for genuine outages — abuse loses goodwill with reviewers.

There is **no rollback to a previous version** in the App Store. Releases are roll-forward only.

---

## Disaster recovery

### Lost distribution certificate / `.p12`

Generate a new one. Apple lets you have multiple distribution certs active simultaneously (max 2), so the failure mode here is an inconvenience, not a months-long blocker. Update the GitHub Secrets, commit a release. The previous cert keeps working until it expires — no impact on installed apps.

### Lost App Store Connect access

Same shape as Android Play Console. Mitigations:

1. Developer team mailbox, not a personal Apple ID.
2. Two **Account Holder** equivalents — actually App Store Connect supports one Account Holder + multiple Admins; ensure at least two team members are Admins.
3. The team mailbox itself has 2FA backup codes printed.

### Account terminated

Apple's appeal process is faster than Google's but still painful. Mitigations:

1. Read the App Store Review Guidelines before launch.
2. Stay clear of the headline pitfalls: misleading descriptions, hidden in-app purchases, copyright issues, location-data abuse, accessibility regressions.
3. If terminated, the appeal goes through the standard channel; expect 1–2 weeks. The app and reviews come back if successful.

---

## Production readiness checklist

- [x] Apple Developer Program $99 paid + enrollment approved
- [ ] App IDs, App Group and capabilities — [`apple_provisioning.md`](../../docs/ops/apple_provisioning.md) steps 2–4 (Background Modes is `Info.plist`, not a portal capability)
- [ ] Distribution certificate, both App Store profiles and the App Store Connect API key in the `production` environment's secrets, the `.p12` and `.p8` backed up in the estate — steps 14–16
- [ ] App Store Connect app record — step 17
- [ ] Listing: description, keywords, support URL, and screenshots at **6.9-inch iPhone** and **Apple Watch** sizes. No iPad set: the app is iPhone-only
- [ ] Privacy policy live at `threkir.com/privacy`
- [ ] App Privacy nutrition label completed, matches policy
- [ ] App Review notes: a working demo account with runs in it; why background location (recording a run with the screen off) and HealthKit are used
- [x] Info.plist usage descriptions all written — guarded by `scripts/check_ios_native_declarations.mjs`
- [x] No web payment link and no Google sign-in button on iOS ([decisions § 1700](../../docs/architecture/decisions.md))
- [x] Watch target builds clean from the `Runner` scheme and is embedded — unsigned, on Xcode 26.4 ([decisions § 1679](../../docs/architecture/decisions.md))
- [ ] First `mobile_ios@` release reaches TestFlight — step 18
- [ ] That build smoke-tested on a real iPhone and a paired Apple Watch: Sign in with Apple, a run recorded with the screen locked, HealthKit import, push, a sandbox purchase, account deletion, one watch run synced
- [ ] Sentry receiving symbolicated native crash reports (dSYM upload step in `release-ios.yml`)
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) iOS column flips from Partial to ✓ once Mac-runtime parity is verified
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) Apple Watch column updated as features pass review
