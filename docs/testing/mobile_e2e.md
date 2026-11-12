# Mobile e2e in CI — short answer

**Yes for Android, conditional yes for iOS, with caveats.** Both are doable. Neither is free. Pick the strategy that matches what you actually want to catch.

This doc exists because "can we run mobile e2e in CI?" is the right question to ask, and the answer depends on what you mean by "e2e" and how much money you want to spend per PR.

## Today

The mobile apps have ~178 widget tests in `apps/mobile_android/test/` (mirrored to `apps/mobile_ios/test/`). Each spins up a Flutter widget tree in a headless `flutter test` runner and asserts on rendered widgets. **These run on every PR** in the `test-packages` CI job — see `.github/workflows/ci.yml`. They are *fast* (~4 min for the whole suite) and don't need a device.

What they don't catch:
- Whether a real emulator can install + cold-launch the APK / IPA.
- Whether the OS-level permission prompts fire in the right order.
- Whether the foreground-service notification + wakelock survive the screen-off transition.
- Whether the OS picks up our deep links from Strava / Garmin OAuth redirects.
- Whether Health Connect / HealthKit imports actually surface real workouts.
- Visual regressions (we have no golden tests today — separate issue).

Closing those gaps is the job of integration tests + e2e tests on a real device or emulator. **The harness exists, and CI runs its Android half** in the `mobile-android-e2e` job ([decisions § 1838](../architecture/decisions.md)); the iOS simulator half has no job. Both apps carry an `integration_test/` target ([decisions § 1820](../architecture/decisions.md)), byte-identical across the twins: `launch_onboarding_test.dart` cold-launches through the real `main()` and pages onboarding to the location disclosure, and `home_navigation_test.dart` reaches Home and switches destinations on the bottom nav. Run them locally with `flutter test integration_test -d <device-id>` from either app. They stop short of every OS dialog by design.

## What "e2e" can mean

Three increasingly expensive tiers:

| Tier | What it is | Where it runs | Per-PR cost |
|---|---|---|---|
| **A. Build smoke** | `flutter build apk` / `flutter build ios --no-codesign` succeeds. | Ubuntu / macOS runner. | Already runs on `main` push (`build-android`, `build-ios` jobs). ~7 min Android, ~10 min iOS macOS. |
| **B. Integration tests** | `flutter integration_test` against a headless emulator / simulator. Real app on real OS. No device farm. | Ubuntu (Android) / macOS (iOS) runner. | ~10–20 min Android, ~15–25 min iOS macOS. |
| **C. Real-device farm** | Same tests, on real devices via Firebase Test Lab / BrowserStack / Sauce / EAS Build. | Cloud farm. | $0.05–$0.25 per device-minute; ~5–15 min per device per PR. |

## Tier A — already in CI

The release-track build smoke is the cheapest defence against "I broke the gradle build". It's running. Keep it running.

Cost: a few minutes of free GitHub Actions Ubuntu compute on every push to `main`, plus macOS minutes (which are billed 10x Ubuntu — verify against the current Actions pricing) for the iOS build.

## Tier B — viable, recommended for Android, expensive for iOS

### Android: `flutter integration_test` on a KVM-accelerated emulator

Wiring:

1. ~~`apps/mobile_android/pubspec.yaml`: add `integration_test:` to `dev_dependencies`~~ **Done** (both twins, § 1820).
2. ~~`apps/mobile_android/integration_test/` directory with `*_test.dart` files~~ **Done**: two suites plus `app_harness.dart`, mirrored to `apps/mobile_ios/integration_test/` and held there by `twin-parity`.
3. ~~GitHub Actions `mobile-android-e2e` job~~ **Done** ([decisions § 1838](../architecture/decisions.md)). `reactivecircus/android-emulator-runner`, SHA-pinned like every action here, on `ubuntu-latest` with KVM opened to the runner user by a udev rule. One API level, not a matrix: **API 34, `google_apis`, `x86_64`** — inside minSdk 26..targetSdk 36, and an x86_64 image is the one KVM accelerates. The AVD and its boot snapshot are cached (`avd-<os>-34-google_apis-x86_64`); a cache miss creates and snapshots it in a first emulator step, and the test step runs with `-no-snapshot-save` so the cached image never carries one run's SharedPreferences into the next. It reuses `build-mobile-android`'s setup verbatim (Flutter pin, pub and Gradle caches, `.env.example` copied over `.env.development`), carries the same `changes.outputs.code` gate and therefore the same draft skip, and is in the `CI gate`'s `needs:`. The command is `flutter test integration_test -d emulator-5554` from `apps/mobile_android`.

   **No Supabase stack.** Neither suite reaches the backend: onboarding is device-local, and `main.dart` routes to Home on the device-scoped `onboarded` flag, not on a session. With `.env.example` in place the debug build carries no seed credentials, so dev auto-login never fires, and its `SUPABASE_URL` (`10.0.2.2:24321`) has nothing listening, so sync takes the shipped offline path. The first suite that signs in adds `.github/actions/start-supabase` to this job and serves it on the host's `10.0.2.2`.

Sample test scope (the first two bullets are what runs today):
- App cold-launches to onboarding.
- Permission rationale dialog renders.
- Sign-in flow completes with the seed user against a `--dart-define=SUPABASE_URL=http://10.0.2.2:24321` stack started by the CI workflow.
- Tap "Start run" → expect run-screen widget tree.

Per-PR cost: ~15–20 min on an Ubuntu runner (free quota), one full APK build + one emulator boot + the test run. The biggest single time-sink is the emulator boot — `reactivecircus/android-emulator-runner` caches AVD snapshots between runs to amortise that.

**Recommendation:** Grow `mobile-android-e2e` to 3–5 critical smoke tests. Skip the full widget-test scope; the integration tests should hit code that widget tests *can't* hit (real GPS permissions, real foreground service, real Health Connect query).

### iOS: `flutter integration_test` on macOS

Same Flutter wiring as Android. The CI changes:

1. Job runs on `macos-latest`. macOS minutes are billed 10x Ubuntu on GitHub-hosted runners.
2. Boot an iOS Simulator (`xcrun simctl boot ...`) before the run.
3. `flutter test integration_test/` with `-d <simulator-id>`.

Per-PR cost: ~20–30 min on macOS runner. At $0.08/min that's ~$1.60–$2.40 *per PR*. For a project with 10–20 PRs / month that's ~$30/month, which is fine; for a high-throughput team it gets expensive.

**Recommendation:** Run iOS e2e on a nightly schedule + on every release tag, not on every PR. Set up a `release-ios.yml` extension that runs the same 3–5 critical tests.

## Tier C — cloud device farms

When you need *real device* coverage (sensor quirks, vendor-specific OEM behaviour, OS versions older than the runner image supports), use a farm. Three options at a similar tier:

| Provider | Pricing model | Strengths |
|---|---|---|
| **Firebase Test Lab** | Per-device-minute; cheapest virtual devices ($1/device-hour); physical devices $5/h | Excellent Android coverage; integrates with Google APIs; the *only* place with rare Pixel + Samsung S-series + non-Google OEM combos at scale |
| **BrowserStack** | Per-user-month subscription | Both Android + iOS; quick to provision; good IDE integration; pricier per minute than FTL but no per-test ceiling |
| **AWS Device Farm** | Per-device-minute; ~$0.17/min | Good iOS coverage; AWS-native; deep integration if the rest of the infra is on AWS |
| **EAS Build (Expo)** | Bundled into EAS pricing | Cheapest *managed* path; less control over device matrix |

Anti-recommendation for this project specifically: BitBar/Sauce Labs are fine but more expensive without compensating features for our scope.

**Recommendation:** Adopt Firebase Test Lab for the Android device matrix (Pixel 6/7/8, Samsung S22/S23, OneUI quirks), nightly schedule, post-release-tag. iOS: defer until we have a specific bug class the simulator misses; iOS simulators are unusually close to real-device behaviour.

## Frameworks worth knowing about

| Tool | What it adds | Verdict for this project |
|---|---|---|
| **Flutter integration_test** | The official, in-tree e2e binding. Same API as widget tests. | Use this. |
| **Patrol** | Wraps integration_test with native-side helpers — tap OS dialogs, swipe notifications, control Bluetooth. Resolves the "can't tap the permission dialog" pain. | Strong yes for any test that needs real OS permission dialogs (we have several: location-always, Bluetooth, Health Connect). |
| **Maestro** | YAML-defined flows that work against installed builds. Cloud or local. | Worth a look for handoff to QA. Less coverage of widget state assertions than integration_test. |
| **Detox** | React-Native-first; works for Flutter but the JS bridge fights us. | Skip. |
| **WebDriverIO / Appium** | Generic mobile automation. | Skip for Flutter — integration_test is strictly better. |

## Practical proposal

If we adopt one thing in the next sprint, it's this:

1. **Per-PR**: keep current widget tests (already there). `mobile-android-e2e` runs the integration_test harness on an emulator via `reactivecircus/android-emulator-runner` (two suites today; grow to five). ~20 min, free-tier quota.
2. **Nightly**: extend to 20+ tests, plus iOS via macOS runner.
3. **Pre-release**: Firebase Test Lab matrix run on Android + manual smoke on iOS Simulator at minimum.

If we adopt two things, add **Patrol** the moment we want to exercise the permission-dialog or Bluetooth-pairing flows. Native dialog tapping is genuinely impossible without it.

If we adopt three things, the third is **golden tests** (Flutter's snapshot-image testing) for visual regressions — that's a separate concern from e2e but commonly bundled in the conversation.

## What it would cost

Estimated monthly CI spend, assuming ~30 PRs / month + nightly + 2 releases:

| Tier | Where | Cost |
|---|---|---|
| Current widget tests | Ubuntu free quota | ~$0 |
| + Android integration_test on PR | Ubuntu free quota (KVM-accelerated) | ~$0 (within free 2k-min quota) |
| + iOS integration_test nightly | macOS runner ~30 min/night | ~$70/month |
| + Firebase Test Lab pre-release on 8 device-min × 4 devices × 2 releases | FTL physical $5/h | ~$5/month |
| **Total** | | **~$75/month** |

If iOS goes on PR instead of nightly: ~$700/month. Defer until clear ROI.

## What this looks like in `.github/workflows/`

The Android half is built: the `mobile-android-e2e` job in `.github/workflows/ci.yml`, described under Tier B above. Read the job itself for the exact steps rather than a copy here, which would drift. The iOS half is not built; it would be a `macos-latest` job booting a simulator with `xcrun simctl` and running the same `flutter test integration_test -d <simulator-id>`, on a nightly schedule per the cost table.

## TL;DR

- **Can mobile e2e run in CI?** Yes.
- **Is it too resource-heavy?** Android: no, fits in free tier. iOS on PR: yes for any non-trivial volume; do it nightly.
- **What blocks adoption today?** The `integration_test/` target and its first two smoke suites landed 2026-10-09 (§ 1820), and `mobile-android-e2e` runs them on an Android emulator per PR (§ 1838). Still missing: a recorded iOS simulator run and an iOS lane, suites for the device-led Android paths (tile cache, foreground service, background sync), and Patrol for the OS-dialog flows.
- **Pick this next** when the manual-testing burden of "did GPS / permissions / Health Connect still work?" outweighs ~1 day of integration-test wiring.
