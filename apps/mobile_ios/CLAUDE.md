# mobile_ios — AI session notes

> **Deferred.** The public landing page lists the iOS app as "Coming soon" and the team is not actively pushing it forward right now. The code stays in lockstep with `mobile_android` via the byte-identical-twin convention so this doesn't bit-rot, but **don't start net-new iOS-led work** (HealthKit, Apple Sign-In hardening, App Store submission prep, etc.) until the deferral is lifted. Twin-parity edits made on Android still need to be mirrored here in the same commit — that's mechanical and stays cheap. See [../../docs/product/parity.md](../../docs/product/parity.md) for the current per-feature state.

Flutter iOS app. **`lib/` and `test/` are now byte-for-byte identical to `apps/mobile_android/`.** Every screen, widget, library, and test is the same file. Platform-specific behaviour (Apple Sign-In vs Google, dotenv vs `--dart-define-from-file`, Apple Watch ingest vs Wear OS bridge, etc.) is dispatched at runtime via `Platform.isIOS` / `Platform.isAndroid` inside the unified files. The pubspec deltas are the package `name` / `description` and nothing else.

## Scope — read before writing code

**Web is the canonical feature surface. This app mirrors web and adds iOS-only capabilities.** See [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) and the live matrix at [../../docs/product/parity.md](../../docs/product/parity.md).

**Build here:**

- **iOS-led features** (the physical-exception list in §24, applied to iOS): live GPS recording with `CLLocationManager.allowsBackgroundLocationUpdates`, on-device crash recovery, BLE chest-strap HR, pedometer / cadence, haptic / TTS pace alerts, OS share sheets, **HealthKit** import (replaces Health Connect on Android), **Apple Sign-In** (replaces Google Sign-In on Android), **Watch Connectivity** ingest from `watch_ios` (already live in `WatchIngestBridge.swift`).
- **Mirroring** of an already-shipped web feature, scoped to the gap analysis in `reviews/mobile-ios/gap-analysis.md` and the iOS rows in `parity.md` where web is `✓` and iOS is `✗` / `Partial`. Use `mobile_android` as the **Flutter implementation reference** (idioms, store shape, screen layout) — not as the feature spec.

**Don't build here first:**

- A user-facing feature that doesn't yet exist on web — build it on web first, mirror after. Same rule as Android per §24.
- An Android-only tile that has no iOS equivalent. **There is no such set today.** The list that stood here — BLE pairing UI, Strava ZIP import, backup/restore, advanced-GPS toggle, dark-mode toggle — predates the twin merge and cited a `screens/settings_screen.dart` comment that no longer exists; all five render on both apps out of the one byte-identical file, none behind a `Platform` gate ([decisions § 707](../../docs/architecture/decisions.md)). A genuinely Android-only tile would need a `Platform` gate and a fresh decision.
- New abstractions / DI frameworks. Match Android's `StatefulWidget + setState + ChangeNotifier` stack — verbatim. The iOS app is "structurally identical to mobile_android" by design (see "What 'done' means" below).
- Direct `Supabase.instance.client.from(...)` calls in screens. Route through `packages/api_client`.
- Comments, decision docs, READMEs. Conventions in [../../docs/architecture/conventions.md](../../docs/architecture/conventions.md) apply in full.

## Current state

**Single-source-of-truth Dart codebase.** `lib/` and `test/` are kept identical to `apps/mobile_android/` via `diff -rq`. There are no iOS-owned screens, libraries, or widgets — every file lives in both apps in the same form, with `Platform.isIOS` / `Platform.isAndroid` branches inside where the runtime actually differs.

**Editing rule:** apply every change to both apps in the same commit. The architecture guard tests run on the android target; iOS will pick up the same code when the Mac build runs.

**Where the platforms diverge inside the unified code:**

| Concern | Android path | iOS path |
|---|---|---|
| Auth (third-party) | Google Sign-In (`google_sign_in`) — needs `GIDClientID` + the reversed-client-id URL scheme in `Info.plist`, neither of which the file carries ([`google_provisioning.md`](../../docs/ops/google_provisioning.md) step 10) | Sign in with Apple (`sign_in_with_apple`) — **ungated on iOS**: `appleSignInAvailable()` returns true for `TargetPlatform.iOS` and `Runner.entitlements` declares `com.apple.developer.applesignin`. It waits on the portal App ID capability, not on a constant |
| Secrets | `.env.local` asset (read by `flutter_dotenv`) | `--dart-define-from-file=dart_defines.json`, mirrored into `dotenv.env` at startup |
| Apple Watch ingest | `WatchIngest.attach` is a no-op (channel never registered) | `Runner/WatchIngestBridge.swift` posts payloads through `run_app/watch_ingest` |
| Wear OS auth bridge | `WearAuthBridge.attach` posts via `run_app/wear_auth` | No-op (`MissingPluginException` caught) |
| Foreground service notification | `RunNotificationBridge` overrides geolocator's notification | No-op (channel not registered) |
| Background sync | `Workmanager().registerPeriodicTask` | iOS uses `BGTaskScheduler` via the same package |
| Background GPS | Geolocator foreground service | `CLLocationManager.allowsBackgroundLocationUpdates` (Info.plist `UIBackgroundModes:location`) |
| Health Connect / HealthKit | `health` package on Android Health Connect | Same package, HealthKit backend |
| Onboarding permission | `Geolocator.requestPermission` (location-when-in-use) | Same `Geolocator.requestPermission` call — no platform divergence |

**Pubspec divergence:** only `name` and `description`. Every dependency, every version, the asset list, and `dev_dependencies` all match. Run `diff apps/mobile_android/pubspec.yaml apps/mobile_ios/pubspec.yaml` — should be exactly two lines.

**Native iOS files under `ios/Runner/`:**

- `AppDelegate.swift` — activates the `WatchIngestBridge` singleton at launch + attaches its method channel when the Flutter engine spins up.
- `CalendarBridge.swift` — **live**: presents `EKEventEditViewController` pre-filled from a club event, handed over the `run_app/calendar` method channel by `lib/calendar_intent.dart`. Asks for write-only calendar access on iOS 17+ (`requestWriteOnlyAccessToEvents`, falling back to `requestAccess` below it) and never reads the calendar. Parses the RRULE value the Dart side sends into an `EKRecurrenceRule` — only the subset `buildRrule` emits, anything else yields no rule rather than a different one (decisions § 692). Registered in `AppDelegate.didInitializeImplicitFlutterEngine`.
- `WatchIngestBridge.swift` — **live**: `WCSessionDelegate` that receives `WCSessionFile` transfers from the watch, reads the gzipped-JSON track contents, and forwards to Dart via the `run_app/watch_ingest` method channel. Payloads arriving before Flutter is ready are buffered in-process and flushed on attach.

## Native tests

`ios/RunnerTests/` carries 48 XCTest cases over the two live bridges. It
replaced the stock `RunnerTests.swift` template stub (`testExample`, empty
body), which had been the entirety of iOS native coverage while the Android
twin shipped three Kotlin bridge suites.

The command, its duplicate-simulator-name trap and the `TEST_HOST` ordering
constraint are in [docs/testing/testing.md § The native suites](../../docs/testing/testing.md).

**The tested seams are a contract.** `WCSession`, `WCSessionFile` and
`EKEventStore` cannot be constructed in a test, so the pure logic is lifted out
of the delegate methods: `CalendarBridge.recurrenceRule(from:)`,
`WatchIngestBridge.routeUserInfo(from:)` and
`WatchIngestBridge.ingestPayload(metadata:track:)`. Keep them internal (not
`private`) and keep them pure, or the coverage goes with them.

`WatchIngestBridge`'s mutable state — the pending buffer, the ingest channel and
the refused-retry budget — lives behind one private serial queue. Two rules
follow and both are pinned by tests: `flushPending` snapshots and clears **under**
the lock but dispatches **outside** it (`dispatch` re-enters the queue, so a
`sync` from inside a held block deadlocks), and internal writes go through
`buffer(_:)` / `requeueRefused(_:)` rather than appending through the computed
`pending` property, which would be a non-atomic read-modify-write.

## Internationalization (i18n)

Shares the Flutter gen-l10n setup with the Android twin ([decisions.md § 113](../../docs/architecture/decisions.md#113-mobile-i18n-uses-flutter-gen-l10n--arb-with-committed-non-synthetic-output-and-a-per-device-locale); full notes in [apps/mobile_android/CLAUDE.md § Internationalization](../mobile_android/CLAUDE.md#internationalization-i18n)). The `lib/l10n/` ARB catalogues + committed `lib/l10n/gen/` output are part of the byte-identical `lib/` surface — they ride the same mirror. iOS-specific: the **seven** locales are advertised in `ios/Runner/Info.plist` via `CFBundleLocalizations` — `pt-PT` was added there alongside `pt-BR` when the European-Portuguese catalogue became reachable (decisions § 547); a locale absent from that array is one the OS will not offer the app in, however complete its ARB. That array is now held to `apps/mobile_android/lib/l10n/` by `test/architecture_guards_test.dart § locale reach`, which reads it through `../mobile_ios/…` so the byte-identical test resolves the same file from either twin's directory (decisions § 740). Apple names a locale by region, and since decisions § 760 so does every other declaration on both twins — `pt-PT` is the canonical tag, the guard's `plistTagOverride` is gone, and the remaining spelling difference is the ARB FILENAME (`app_pt.arb`, which gen-l10n requires as the bare Portuguese base), recorded in the guard as `arbTagOverride`. After regenerating l10n on Android, copy `lib/l10n/gen/` here in the same commit.

## What "done" means

Structurally identical to `mobile_android` (same stack, same `StatefulWidget + setState` pattern, same dependence on `packages/run_recorder` and `packages/api_client`). Every module in `mobile_android/lib/` that isn't Android-specific is a candidate to hoist into a shared package before the iOS port — ask before doing that; the team may prefer copy-then-converge.

## What this app will look like when it's done

Android-specific concerns that don't port:
- Foreground service for background GPS → iOS uses `CLLocationManager.allowsBackgroundLocationUpdates` (already done via run_recorder + Info.plist UIBackgroundModes:location).
- Health Connect importer → replaced by HealthKit importer.
- Google Sign-In flow → replaced by Apple Sign-In.
- Disk-backed tile cache → the same `flutter_map_cache` + `dio_cache_interceptor` combo works.

iOS-only concerns with no Android analogue:
- **Watch run ingest.** `WatchIngestBridge.swift` is live. The `WatchIngestQueue` now persists unauthenticated payloads to disk and replays them on sign-in — no runs are lost across restarts. Previously the in-process `pending` buffer was lost on app restart.

## Catch-up status

- **Builds and boots, clean, on current toolchain — 2026-09-20.** `flutter build ios --simulator --no-codesign` succeeds with **zero** source changes needed (Xcode 26.4, Flutter 3.44.8), and the built `.app` launches on an iPhone 17 Pro / iOS 26.4 simulator, reaching onboarding and — past the `onboarded` pref — the full Home dashboard. Runtime log across four launches: no `MissingPluginException`, no `PlatformException`, no unhandled exception, no permission or plist lookup failure. `Supabase init completed` confirms `--dart-define-from-file` reaches Dart; `WCSession initialized` confirms `WatchIngestBridge` activates. `dart analyze lib test` is 0 warnings / 0 errors. Two things this does NOT prove: no feature row was exercised (`simctl` has no tap primitive — driving the UI needs `integration_test` or a device), and nothing was code-signed, so archiving an IPA remains untested. **`parity.md` cells did not move on the strength of this run.**
- **Native bridge tests — 2026-09-20.** `ios/RunnerTests/` carries real XCTest coverage of both live bridges, replacing the stock `RunnerTests.swift` template stub. See **Native tests** below.
- **Plugins resolve through Swift Package Manager, not CocoaPods.** `Podfile.lock` legitimately lists only `Flutter`, `flutter_tts`, `health` and `workmanager_apple` — the three plugins without SPM support. Everything else (geolocator, firebase, permission_handler_apple, sign_in_with_apple, purchases, sentry…) is a local package under `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage`. A four-pod lock reads as stale and is not; a `post_install` hook in the `Podfile` reaches almost nothing.
- **First simulator launch — done 2026-06-06.** The iOS app builds and boots to onboarding on an iPhone simulator for the first time. Three launch blockers were fixed: (1) `AppDelegate.swift` now calls `WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.threkir.backgroundSync", …)` — without it the Dart-side `registerPeriodicTask` submit aborted the process (`SIGABRT`, "submission without registration"); (2) the Runner `IPHONEOS_DEPLOYMENT_TARGET` was bumped 13.0 → 15.0 to match the Podfile + `health` (15.0) and `workmanager_apple` (14.0) — importing `workmanager_apple` from a 13.0 unit wouldn't compile; (3) two byte-identical-twin `main.dart` fixes — the flutter_dotenv `mergeWith: dotenv.env` footgun that wiped the dart-define secrets (`hasSupabase` came back false), and the unguarded `RaceController.start()` that aborted the isolate when Supabase wasn't initialised. Stale CocoaPods + SPM lockfiles were refreshed alongside. **Feature-by-feature runtime verification (and the `parity.md` cell flips) is still pending — a clean boot is not feature parity.**
- **Code parity done.** `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` and `diff -rq apps/mobile_android/test apps/mobile_ios/test` both return empty. The iOS-owned screens were merged with the Android twins via `Platform.isIOS` / `Platform.isAndroid` branches inside the unified files. Six previously-iOS-owned files (`main.dart`, `home_screen.dart`, `onboarding_screen.dart`, `run_screen.dart`, `settings_screen.dart`, `sign_in_screen.dart`, `sign_up_screen.dart`) now live as a single source-of-truth file used by both apps.
- **Info.plist** — every Apple usage-description key the Flutter plugins require is now in `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription` + `NSLocationAlwaysAndWhenInUseUsageDescription` (geolocator), `NSHealthShareUsageDescription` (health → HealthKit), `NSBluetoothAlwaysUsageDescription` (flutter_reactive_ble), `NSMotionUsageDescription` (pedometer), `NSPhotoLibraryUsageDescription` (image_picker for run photos), `NSCalendarsWriteOnlyAccessUsageDescription` + `NSCalendarsUsageDescription` (`CalendarBridge.swift`; write-only is the whole ask — decisions § 692). `UIBackgroundModes` carries `location` + `processing` (NOT `fetch` — background sync runs via `BGTaskScheduler`/`processing`, not background app refresh; reconciled with the plist per audit-findings 2026-05-30 Medium) and `BGTaskSchedulerPermittedIdentifiers` includes `com.threkir.backgroundSync` so the Workmanager periodic task can register. Without these the corresponding features fail silently — adding them removes a runtime-only failure mode that wouldn't have surfaced until a user denied an invisible permission prompt. **Superseded (2026-09-20).** A 2026-06-06 note here said the Dart side submits a `BGAppRefreshTaskRequest`, that this needs the `fetch` background mode, and that the submit is rejected on a real device so background sync never runs. All three are now false and the reconciliation they described is done: `background_sync.dart`'s iOS branch calls `Workmanager().registerProcessingTask`, `AppDelegate.swift` calls `WorkmanagerPlugin.registerBGProcessingTask`, and `UIBackgroundModes` carries `processing` (alongside `audio` + `location`) — the three agree, and a simulator run on 2026-09-20 logged `submitTaskRequest: <BGProcessingTaskRequest: com.threkir.backgroundSync…>` accepted on every launch with no rejection. `fetch` is deliberately absent.
- **Feature-level runtime parity** is the next gate — the target builds and boots (below), which is not the same thing. `ios/Runner/Runner.entitlements` now exists and declares `com.apple.developer.healthkit` (wired into all three Runner build configs via `CODE_SIGN_ENTITLEMENTS`; pinned by the `iOS Info.plist` group in `architecture_guards_test.dart`) — added per audit/app-store-privacy (2026-05-30) Critical, which flagged that the missing capability is an App Store reject + a runtime crash on the first HealthKit call. Sign-in-with-Apple still needs its own entitlement entry + Apple Developer-portal Services ID. Remaining Mac-only validation: archiving the IPA to confirm the entitlement signs cleanly, `pod install` for the native plugins, `permission_handler` configuration. `parity.md` cells flip when each row is verified on a simulator or device.

## Recommended approach for a new task here

1. **Feature spec lives on web; Flutter idiom lives on Android.** When deciding *what* a screen does, read the web component (`apps/web/src/lib/components/...` or `apps/web/src/routes/...`) and `parity.md`. When deciding *how* to write a Flutter screen, look at the corresponding `apps/mobile_android/lib/screens/...` for the idiom, store wiring, and api_client usage. Don't invent a new feature on iOS — that violates §24.
2. **If the task is "port the latest Android change to iOS,"** copy the file verbatim (or apply the same diff) — the convergence cost stays low only as long as the twins don't drift.
3. **If the task is "fix iOS-only behaviour,"** keep the change in the four iOS-owned files (`main.dart`, the three iOS-owned screens) or in `ios/Runner/`. Don't fork a verbatim copy unless there is no other way.
4. **Prefer lifting shared code into a package** (`packages/ui_kit`, a new `packages/local_stores`, etc.) over deepening the verbatim duplication when a third client (or shared test surface) will need it. The bar for extracting a package is "more than two clients consume the same file or the file gets meaningfully edited on one twin without the other catching up."

## Dart analyzer

No warning or error level issues. The app carries ~20 info-level lints (mostly `always_use_package_imports` and `unnecessary_library_name`) — treat as noise per repo policy.

## Running it locally

See [local_testing.md](local_testing.md). You need an iOS simulator or a paired device.

## Deploying to production

See [deployment.md](deployment.md) — App Store Connect setup, distribution cert + provisioning profile, ASC API key, Apple Watch bundling, observability, rollback, DR. The Apple Watch app at `apps/watch_ios/` ships inside this app's IPA — no separate listing. `Runner.xcodeproj` carries a `WatchApp` target that **references** the Swift sources under `apps/watch_ios/WatchApp/` (never copies them) and an Embed Watch Content phase that puts the product at `Runner.app/Watch/WatchApp.app`; `apps/watch_ios/WatchApp.xcodeproj` remains as the test host CI builds. Adding or removing a watch source or resource means editing both projects — claim (15) of `scripts/check_watch_ios_source.mjs` fails the PR when they diverge or when the embed goes. `ios/Flutter/WatchApp.xcconfig` maps Flutter's version onto the watch target so the two bundles agree, which App Store upload requires. See [decisions § 1679](../../docs/architecture/decisions.md).

The iOS Runner project uses Swift Package Manager + CocoaPods in hybrid mode (most plugins via SPM, `health` still via pods). Podfile pins `platform :ios, '15.0'`. Secrets for `flutter run` pass through `dart_defines.json` (gitignored) because inline `--dart-define=` flags break on the `sb_publishable_…` Supabase anon key format. Rationale: [../../docs/architecture/decisions.md § 13](../../docs/architecture/decisions.md).

## Before reporting a task done

- Update the iOS checkbox in `roadmap.md` (there are several — "Parse on iOS", etc.).
- If you ported a screen from `mobile_android`, note the source commit in the PR description so future drift fixes can find the twin.
- If the ported screen pulled in a dependency that isn't in Android, add it here so the divergence is visible.
