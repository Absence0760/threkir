# Mobile iOS deployment plan

How `apps/mobile_ios/` ships to the Apple App Store, including the bundled `apps/watch_ios/` Apple Watch target.

Operational counterpart of [`apps/mobile_ios/CLAUDE.md`](CLAUDE.md) and the byte-identical-twin convention with `apps/mobile_android/` ([decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md). For tag-driven release mechanics see [`docs/ops/releasing.md`](../../docs/ops/releasing.md).

**Status: plan.** The Dart code is at parity with Android (same `lib/`, same `test/`); native iOS work + entitlements + a Mac runtime smoke run are the remaining gates.

---

## What this doc covers

The iOS app and the Apple Watch app are **one deployment**. The watch app is a target of `Runner.xcodeproj` and is copied into the iOS app's `.ipa` by an Embed Watch Content phase, so there's no separate listing, no separate review, no separate upload. The Swift sources live under `apps/watch_ios/` and are **referenced** from the phone project rather than copied — one copy on disk, two targets. `apps/watch_ios/WatchApp.xcodeproj` also stays, as the test host the `test-watch-ios` CI job builds; claim (15) of `scripts/check_watch_ios_source.mjs` fails a PR when the two projects stop describing the same app. See [decisions § 1657](../../docs/architecture/decisions.md).

So: `mobile_ios@1.2.3` triggers one CI workflow that ships **both** apps.

---

## Provider — Apple App Store Connect

**Distribution:** App Store + TestFlight. **There is no third option** — Ad Hoc caps at 100 pre-registered devices, the Enterprise program is for an organisation's own employees, and the EU's DMA Web Distribution route requires an EU-established entity with over a million first annual EU installs behind it. The website links to the App Store; it never serves an `.ipa`. See [decisions.md § 379](../../docs/architecture/decisions.md).

**TestFlight first.** Internal testers (up to 100 Apple IDs in the developer team) and external testers (up to 10,000 via a public TestFlight link) can install before the App Store rollout. Treat TestFlight as the equivalent of Play's Internal track.

**Bundle IDs:**

```
com.threkir.app            ← iOS phone app
com.threkir.app.watchapp ← Apple Watch app target
com.threkir.app.watchapp.WidgetsExtension  ← (when the complication ships)
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
   the **Team ID** (10 chars, Membership details — it is also `APNS_TEAM_ID`, so
   it already has a home in `threkir/push-credentials.sops.yaml`), the Apple
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

3. **Register the App Group first**, at developer.apple.com → Identifiers → **App Groups**: `group.com.threkir.app.activerun`. It is a separate identifier type, so it cannot be ticked on an App ID that does not yet have it registered. The id is **not** `group.com.threkir.app` — the canonical spelling is centralised in [`apps/watch_ios/WatchApp/ActiveRunBridge.swift`](../watch_ios/WatchApp/ActiveRunBridge.swift) and declared in `WatchApp.entitlements`; a mismatch silently shares nothing.
4. **Create the App ID** at developer.apple.com → Identifiers → App IDs → App:
   - Bundle ID: `com.threkir.app` (Explicit)
   - Capabilities: **HealthKit** (leave Clinical Health Records off — we read workouts, not records), **Sign in with Apple** (Configure → *Enable as a primary App ID*), **Push Notifications**, **App Groups** (select the group above), and **Associated Domains** only if universal links ship — nothing serves an `apple-app-site-association` today.
   - **Not** Background Modes: it is not a portal capability at all. It lives in `Info.plist`'s `UIBackgroundModes`, already committed and guard-enforced by `scripts/check_ios_native_declarations.mjs` (decisions.md § 742).
   - **Not** Maps: `com.apple.developer.maps` registers a *routing* app that publishes directions coverage. The watch mini-map draws our own polyline through MapKit, which needs no capability.
5. **Create the Watch App ID:**
   - Bundle ID: `com.threkir.app.watchapp`
   - Capabilities: **HealthKit**, **App Groups** (the same group — this is the side that actually declares it today; the phone's `Runner.entitlements` carries no app-group entitlement yet, so the bridge's phone half is still owed)
6. **Provisioning profiles.** Create App Store distribution profiles for both bundle IDs. Set the team to your Developer Program team. Download the `.mobileprovision` files.
7. **Create the App Store listing** at App Store Connect:
   - App information (name, primary category Health & Fitness, content rights)
   - App privacy (next section)
   - Pricing — Free, available worldwide minus the regions we're skipping
   - In-App Purchases — RevenueCat will populate this once SDK is wired

---

## Signing setup

### Generate the distribution certificate (one-time)

In Keychain Access on a Mac:

1. Certificate Assistant → Request a Certificate from a Certificate Authority. Email = the developer team mailbox. Choose "Saved to disk".
2. developer.apple.com → Certificates → "+" → iOS Distribution → upload the `.certSigningRequest` from step 1.
3. Download the issued `.cer`. Double-click to install in Keychain Access.
4. In Keychain Access, find the certificate. Expand to see the private key. Right-click → Export → save as `threkir-distribution.p12` with a password.
5. `base64 -i threkir-distribution.p12 | pbcopy` → paste into GitHub Secret `IOS_BUILD_CERTIFICATE_BASE64`.

### App Store Connect API key (one-time)

This is what lets CI upload to TestFlight without a maintainer's Apple ID password.

1. App Store Connect → Users and Access → Keys → "+" → name "GitHub Actions", access "App Manager".
2. Download the `.p8` file. **You can only download it once** — save it sops-encrypted into the estate secrets repo (`../infra-secrets`, same pattern as the Android upload keystore).
3. Note the **Key ID** and **Issuer ID** shown on the same page.

### GitHub Secrets required

| Secret | Source |
|---|---|
| `IOS_BUILD_CERTIFICATE_BASE64` | base64 of `threkir-distribution.p12` |
| `IOS_P12_PASSWORD` | the password from the export step |
| `IOS_PROVISIONING_PROFILE_BASE64` | base64 of the iOS app's `.mobileprovision` |
| `IOS_WATCH_PROVISIONING_PROFILE_BASE64` | base64 of the Watch app's `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | a throwaway, gates the ephemeral keychain on the runner |
| `APP_STORE_CONNECT_API_KEY_ID` | the Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | the Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | base64 of the App Store Connect `.p8` |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | base64 of `GoogleService-Info.plist` from the Firebase project's `com.threkir.app` iOS app. **Not optional, signing or not**: the Runner target copies that plist into the bundle, and the file is gitignored, so the workflow fails without it — deliberately, and before Xcode does. Runbook in [`docs/features/native_push.md` § Operator provisioning](../../docs/features/native_push.md#operator-provisioning-the-credential-gate) |

---

## Build configuration

### Build flavours

Same shape as Android: `dev` and `production` build configurations, gated on `xcconfig` files.

| Configuration | Bundle ID | Backend |
|---|---|---|
| `Debug-Dev` | `com.threkir.app.dev` | Local Supabase |
| `Release-Dev` | `com.threkir.app.dev` | Staging Supabase |
| `Release-Production` | `com.threkir.app` | Production Supabase |

### Production secrets via `dart_defines.json`

The iOS toolchain doesn't accept Supabase's `sb_publishable_...` keys via inline `--dart-define=` — the underscores break Xcode's argument parsing ([decisions.md § 13](../../docs/architecture/decisions.md)). Instead the workflow writes a temporary `dart_defines.json`:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "MAPTILER_KEY": "...",
  "REVENUECAT_API_KEY": "appl_...",
  "SENTRY_DSN": "https://...@sentry.io/..."
}
```

Then `flutter build ipa --release --dart-define-from-file=dart_defines.json`. The file is gitignored; the workflow generates it from secrets, builds, then deletes.

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
- `NSCameraUsageDescription` — taking a photo on the run
- `NSCalendarsWriteOnlyAccessUsageDescription` (iOS 17+) + `NSCalendarsUsageDescription` (the pre-17 fallback) — adding a club event to the calendar. Write-only is the whole ask: the app hands `EKEventEditViewController` a pre-filled event and never reads the calendar (decisions § 692)

Required keys:

- `UIBackgroundModes` array containing `location` (background GPS) and `workout-processing` (Apple Watch session)
- `WKApplication` (in the watch target's Info.plist) — true. This is the
  single-target key; `WKWatchKitApp` is the legacy two-target spelling and
  this project does not use it.
- `WKCompanionAppBundleIdentifier` — `com.threkir.app`. Declared since
  2026-09-18, after the embed it describes actually existed; `WKWatchOnly`
  is gone, the two being mutually exclusive. That was step 3 of the
  five-step sequence in decisions § 1256, and § 1657 records steps 1–4.

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
- App Groups → `group.com.threkir.app.activerun` (declared today only by the watch app; shared with the iOS app and the future complication target when their halves land — see [`apps/watch_ios/Complications/README.md`](../watch_ios/Complications/README.md))

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

Triggered by tagging `mobile_ios@1.2.3`. The workflow at `.github/workflows/release-ios.yml`:

1. Checks out the tag on a `macos-latest` runner.
2. Sets up Flutter SDK + CocoaPods.
3. Decodes the `.p12` cert into an ephemeral keychain (gated by `KEYCHAIN_PASSWORD`).
4. Decodes both `.mobileprovision` files into `~/Library/MobileDevice/Provisioning Profiles/`.
5. Reads version from tag, derives build number from `git rev-list --count HEAD`.
6. Writes the production `dart_defines.json`.
7. `flutter build ipa --release --export-options-plist=export-options.plist`.
8. Uploads to App Store Connect via `xcrun altool` using the API key.
9. Creates a GitHub Release with the IPA attached.

Lands the build in **TestFlight** (the equivalent of Play's Internal track). Promotion to App Store is manual through App Store Connect after a smoke test.

The `release-ios.yml` workflow is currently a skeleton ([releasing.md](../../docs/ops/releasing.md) notes the secrets are commented out). Uncomment once the Apple Developer team is set up + the certs exist.

---

## Apple Watch specifics

### What ships in the IPA

The Apple Watch target is a separate scheme in the same Xcode project. `flutter build ipa` compiles it as a Watch Extension and embeds it in the IPA. Users who install the iOS app see the Watch app appear in the iOS Watch app's "Available apps" list, where they can install it on their paired watch.

There's no separate review for the Watch app. App Store review covers both targets in one pass; the reviewers test on a paired watch + phone simulator.

### HealthKit entitlements (Watch)

The Watch target needs its own HealthKit entitlement (separate from the iOS one). Set up at developer.apple.com → Identifiers → `com.threkir.app.watchapp` → enable HealthKit.

### Watch Connectivity

The phone-watch transport is `WCSession.transferFile(_:metadata:)` (decisions.md § 40). The phone-side `WatchIngestBridge.swift` is **live**; the queue persists pre-auth payloads to disk via `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` so a phone restart between watch transfer and sign-in doesn't lose the run. No additional setup at deploy time — entitlements travel with the App Group.

### Active-run complication

The Complications target ([`apps/watch_ios/Complications/README.md`](../watch_ios/Complications/README.md)) requires its own bundle ID + provisioning profile if/when it ships. Currently scaffolded but not built — `parity.md` shows it as `Partial`. When the complication target lands, add a `IOS_COMPLICATION_PROVISIONING_PROFILE_BASE64` secret and update the workflow.

---

## Observability

Same Sentry mobile project as Android — different DSN platform tag, same dashboard. Apple-specific surfaces:

| What | Where |
|---|---|
| Crash reports | Sentry mobile project + Xcode Organizer (post-launch) |
| Energy / power metrics | Xcode Organizer → Energy / Hangs |
| Adoption rate | App Store Connect → Analytics |
| User reviews | App Store Connect → Ratings and Reviews |

**Sentry on iOS gotcha.** `sentry_flutter` requires a build-phase script in the Runner target (`scripts/sentry-upload.sh`) that uploads dSYMs after every release build. Without it, crashes appear as raw memory addresses instead of symbolicated stacks. Adding this is part of the "uncomment the iOS release workflow" milestone.

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

- [ ] Apple Developer Program $99 paid + enrollment approved
- [ ] Bundle IDs registered at developer.apple.com (iOS + Watch)
- [ ] Capabilities enabled on both bundle IDs (HealthKit, Sign in with Apple, Push, App Groups — Background Modes is `Info.plist`, not a portal capability)
- [ ] App Store Connect listing created (description, keywords, support URL, screenshots — required at iPhone 6.7", iPhone 5.5", iPad 12.9", Apple Watch screen sizes)
- [ ] Privacy policy live at `threkir.com/privacy`
- [ ] App Privacy nutrition label completed, matches policy
- [ ] Distribution certificate generated, sops-backed-up in the estate secrets repo, and set as GitHub Secrets
- [ ] Provisioning profiles for both bundle IDs in GitHub Secrets
- [ ] App Store Connect API key created, in GitHub Secrets
- [ ] Production `dart_defines.json` values verified
- [ ] Info.plist usage descriptions all written
- [ ] Watch target builds clean from `mobile_ios` scheme
- [ ] First TestFlight build smoke-tested on a real device + a real Apple Watch
- [ ] Sentry receiving symbolicated crash reports (dSYM upload script live)
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) iOS column flips from Partial to ✓ once Mac-runtime parity is verified
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) Apple Watch column updated as features pass review
