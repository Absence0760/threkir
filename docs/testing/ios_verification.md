# iOS runtime verification pass

The repeatable pass that converts the **iOS column** of [parity.md](../product/parity.md) from derived to observed, and the log of what each attempt actually reached.

[parity.md § What an iOS cell means](../product/parity.md#what-an-ios-cell-means) says the column is not an observation: `apps/mobile_ios/lib/` and `test/` are byte-identical to `mobile_android` (decisions § 39), so every iOS cell is computed from its Android cell, and the only thing a row may add for itself is an obstruction on the iOS side of the shared Dart. That is honest, and it is also a debt. This file is how the debt gets paid — once, deliberately, with evidence — rather than by a session that launches one screen and starts ticking.

For the per-feature recipes, use [manual_testing.md](manual_testing.md). This file does not restate them; it says which of them an iOS pass can reach, on what hardware, and what each result is allowed to claim.

---

## The column converts in one move, not 305

`scripts/check_parity_ios_column.mjs` refuses an iOS `✓` on any row, whatever its Notes say — the constant is named `UNEARNABLE`. There is no per-cell path to a tick, by design. What changes when the pass succeeds is **one line of the derivation table** inside the `<!-- parity-ios-rule -->` block:

```
| Android cell | iOS cell  |
| `✓`          | `Partial` |     ← this line
```

and then the whole column is swept again in one pass. So an iOS verification run is **pass/fail as a body of evidence**, not 305 independent verdicts. A run that exercises nine screens has not converted nine cells; it has produced nine data points toward one decision.

Two things a run *can* change per row, because they are departures rather than ticks:

- A row whose Notes name an iOS obstruction (`**iOS <symbol>:** <why>`) the tree no longer supports — the justification is stale, and the cell returns to the derivation.
- A row that **needs** such a marker because the pass found an obstruction nobody had recorded. This is the most valuable output of a run: before the column converts, it is the only kind of iOS finding the matrix has a place for.

---

## The rung a result may claim

The project's verification ladder is defined in [quality_standards.md](../custom_watch/quality_standards.md) for the watch firmware. The same four rungs, restated for the phone — with the same rules that a rung is **never** inherited and a lower one **never** stands in for a higher one:

| Rung | What earns it on the phone | What it says nothing about |
|---|---|---|
| **host-tested** | `flutter test` green in `apps/mobile_ios` or the shared packages. The Dart logic is pinned. | The target, the OS, any plugin's native half, any permission, any device capability |
| **build-verified** | The Runner target links for the target including every plugin's iOS pod / SPM product, **and** the key or entitlement the feature needs is read back out of the *built* product rather than out of source | Runtime behaviour of any kind |
| **sim-verified** | The unmodified build ran on a named iOS Simulator and a **named observable changed as predicted** | Real GNSS, any radio, real HealthKit data, camera, background execution, power, thermals, real networks, and anything only a release build does |
| **bench-verified** | The same build ran on a **real iPhone** and a recorded observation met a stated criterion | Other iPhone models, other iOS versions, App Review behaviour |

**Only bench-verified converts the derivation table.** Not conservatism for its own sake: the `✓ → Partial` line is a claim about the entire shipped surface, and the capability classes a simulator cannot reach (below) cut across the recording stack, the integrations, the permissions model and the background lifecycle — which is most of what the matrix's rows are about. A simulator pass is worth running because it cheaply eliminates whole classes of failure before anyone picks up a phone, not because it finishes the job.

---

## Three traps that cost a session each

1. **`flutter build ios --simulator` is always a DEBUG build.** `flutter build ios --help` states it outright: the flag *"changes the default build mode to debug if otherwise unspecified"*, because Flutter has no AOT snapshot for the simulator. Two consequences that look like features. `apps/mobile_ios/.env.development` is loaded behind `kDebugMode` in `lib/main.dart`, so the simulator build **auto-signs-in to the seed account against loopback Supabase and sets `BYPASS_PAYWALL=true`** — a signed-in home screen full of data is not evidence that sign-in works in the shipped app. And nothing about release-mode tree-shaking, assertions-off behaviour, or the dotenv bridge decisions § 709 exists because of, is exercised at all. Confirm which you built by looking for `Runner.app/Frameworks/App.framework/flutter_assets/kernel_blob.bin` — present means debug/JIT. **The simulator can never verify release behaviour; only a device archive can.**
2. **`--no-codesign` embeds no entitlements.** `codesign -d --entitlements - Runner.app` on such a build prints the executable path and nothing else. Every entitlement claim — HealthKit, Sign in with Apple, APNs — has to be read from a **signed** build, not from the simulator one. Reading `Runner.entitlements` in the source tree is weaker again: it proves what was requested, not what was granted by a provisioning profile.
3. **The local Flutter is not the CI Flutter.** CI pins `FLUTTER_VERSION` in [.github/workflows/ci.yml](../../.github/workflows/ci.yml). A workstation on a different stable builds a different engine, a different set of framework diagnostics, and a different plugin resolution. Record both versions in every result. Bumping the pin is a deliberate act (decisions § 595), so the honest move is to match CI before the run that counts, not to explain the gap afterwards.

---

## What the simulator cannot do

Write this down before every run, because the temptation is to read "the screen appeared" as "the feature works".

| Capability | Simulator reality | What that removes from a sim-verified claim |
|---|---|---|
| GNSS | `simctl location` injects a perfect, noiseless, never-dropping fix. No accuracy variation, no cold-fix latency, no multipath, no dropout. | Everything whose behaviour is *a response to bad GPS*: auto-pause tuning, the GPS-lost banner and its dropout count, off-route hysteresis (40 m on / 20 m off), distance accuracy, the filter chain, GPS elevation |
| Bluetooth | **No radio at all.** | BLE heart-rate strap, FTMS treadmill, every scan / pair path |
| HealthKit | The framework and an empty store exist. No Apple Watch data, no third-party samples, and nothing seeds the store without hand entry in the Health app. | A real HealthKit import. The authorization sheet and an empty-store read are reachable |
| Camera | Absent. `simctl addmedia` seeds the photo **library**, so picking is reachable; capture is not. | Nutrition barcode scan; camera capture for run photos |
| Push | No APNs registration, so no device token. `simctl push` presents a synthetic payload only. | Token registration, real delivery, background push wake |
| Background execution | No real suspension, no jetsam, no Low Power Mode, no thermal throttle. | Background location continuation, `BGTaskScheduler` periodic sync, surviving a backgrounded hour |
| Purchases | RevenueCat sandbox wants a real device and a sandbox Apple ID. | Upgrade flow, restore purchases, store-originated tier changes |
| Sensors | No barometer; Core Motion returns nothing useful. | Step count, cadence, indoor / treadmill distance |
| Network conditions | The host's network, unshaped. | Offline → online drain timing, flaky-network retry behaviour |
| Performance | The Mac's CPU and memory. | Frame rate, battery, memory pressure, thermals |

The corollary: a simulator pass is strongest on **cold launch, auth, reads and writes against a backend, navigation, layout, text scaling, localization, and what is actually inside the built bundle** — and worthless on the recording stack, which is the product.

---

## The pass

### Step 0 — preconditions

```bash
cd apps/backend && supabase start && supabase status -o env   # seeded backend
grep -n "FLUTTER_VERSION" .github/workflows/ci.yml            # match it before the run that counts
flutter --version
xcrun simctl list devices available | grep iPhone
xcrun simctl boot <UDID>
```

Map tiles need `MAPTILER_KEY` or the local Protomaps server (`bin/protomaps-dev.sh start`, [protomaps_local_setup.md](../ops/protomaps_local_setup.md)). Without one, every map surface draws its overlays on a blank background — a legitimate *fallback* observation, not a verification of the map.

### Step 1 — build-verified sweep

```bash
cd apps/mobile_ios
flutter build ios --simulator --no-codesign     # DEBUG — see trap 1
```

The single most load-bearing command in the pass, because it settles an obstruction class the derivation rule names explicitly: **"a plugin that does not declare iOS"**. A green link means every plugin in `pubspec.yaml` resolved an iOS pod or SPM product and every bridge in `ios/Runner/` compiles. Read the plugin warnings, not just the exit code — Flutter names the plugins that fell back from SPM to CocoaPods, and that list is the early warning for the next toolchain bump.

For a run that is meant to count, also build what ships: `flutter build ipa` (signed) exercises release mode and produces the artefact whose entitlements can actually be read.

### Step 2 — read the shipped bundle, not the source

Source can say anything; this reads what was produced.

```bash
APP=build/ios/iphonesimulator/Runner.app
plutil -p "$APP/Info.plist"
ls "$APP/Frameworks"      # only DYNAMIC frameworks — SPM and static pods link into the binary
ls "$APP"/*.lproj
ls "$APP/Frameworks/App.framework/flutter_assets/kernel_blob.bin"   # present ⇒ debug build
```

Per feature the row claims, check: the `NS*UsageDescription` string, the `UIBackgroundModes` value, the `BGTaskSchedulerPermittedIdentifiers` id, the `CFBundleURLTypes` scheme, and the `CFBundleDocumentTypes` + `UTImportedTypeDeclarations` **pair** for every file extension an import row names.

**A declared extension with no resolvable UTI is an obstruction.** iOS will not offer the app under "Open with" for it, and a `FileType.custom` picker resolves an unmatchable dynamic UTI and greys it out. Neither is visible from the Dart side, which is exactly why this step exists.

Entitlements are **not** readable here (trap 2) — take them from the signed build.

### Step 3 — install and cold launch

```bash
xcrun simctl install <UDID> "$APP"
xcrun simctl launch <UDID> com.threkir.app
xcrun simctl io <UDID> screenshot shots/01-launch.png
```

Screenshots are cheap and they are evidence. Name them for the step and keep them with the result. `flutter run -d <UDID>` gives the same build plus a live log and hot reload.

### Step 4 — what `simctl` can drive without hands

The observables a scripted run can change and re-run identically:

| Lever | Command | Observable |
|---|---|---|
| Text size | `xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large` | Overflow and truncation at OS text scales. Note the **underscore** — `content-size` is rejected with a usage dump and no error exit |
| Appearance | `xcrun simctl ui <UDID> appearance light\|dark` | Theme follows the OS |
| Contrast | `xcrun simctl ui <UDID> increase_contrast enabled` | Increase-Contrast handling |
| Location | `xcrun simctl location <UDID> set <lat>,<lon>` / `... start` | Map centres, recorder ingests fixes. A *perfect* signal only |
| Permissions | `xcrun simctl privacy <UDID> grant\|revoke\|reset location com.threkir.app` | Prompt copy is the `Info.plist` string; a mid-session revoke surfaces the banner |
| Photo library | `xcrun simctl addmedia <UDID> <file>` | The picker path for run photos |
| Push presentation | `xcrun simctl push <UDID> com.threkir.app payload.apns` | The notification renders and a tap routes. **Not** delivery |
| Cold kill | `xcrun simctl terminate <UDID> com.threkir.app` | The unsaved-run recovery prompt on next launch |
| Deep link | `xcrun simctl openurl <UDID> "com.threkir.app://…"` | **Needs a tap** — see below |

**`simctl openurl` does not complete unattended.** A custom-scheme or `file://` open raises a SpringBoard *"Open in \"Threkir\"?"* confirmation with Open / Cancel. That alert proves the scheme or document type resolved to the app — real build-verified evidence — but the app never receives the URL until someone taps Open, and the alert **survives `simctl terminate` and relaunch**. Only a simulator `shutdown` + `boot` clears it, so a script that fires `openurl` and carries on is screenshotting a modal, not a feature.

### Step 5 — the screens that need hands

There is **no UI automation for the Flutter apps**: no `integration_test/` directory exists in either mobile target, mobile e2e is out of scope by design ([testing.md](testing.md)), and `simctl` has no tap primitive. Every screen past the launch destination has to be walked by a person, and a scripted run can claim none of it.

Walk [manual_testing.md](manual_testing.md) top to bottom on the simulator, skipping the rows the capability table marks unreachable, and record one line per scenario: what you did, what you saw, the rung. This is the bulk of the pass and it does not compress.

### Step 6 — the device leg

Everything the capability table removes, on a real iPhone, outdoors where the row is about GPS. This is the leg that earns the derivation-table change. It is tracked as one item in [followups.md](../product/followups.md), not per row.

---

## Recording a result

Append a dated block below. Rules, in the spirit of [quality_standards.md](../custom_watch/quality_standards.md):

- **Name the rung on every line.** "Works" is not a result; "sim-verified: the home screen listed 20 runs" is.
- **Name the build** — debug or release, which Flutter, which simulator UDID and iOS version.
- **A screenshot or a captured log, or it did not happen.**
- **Say what you could not reach**, not only what you did. A result listing only passes is unreadable as evidence.
- **Do not convert a cell from here.** An obstruction found gets a `**iOS <symbol>:** <why>` marker on that row. A column that looks ready is a *proposal* to change the derivation table, and it needs the device leg behind it.

---

## Results log

### 2026-09-21 — first scripted pass (simulator only)

**Build:** `flutter build ios --simulator --no-codesign` — **debug**, per trap 1, confirmed by a 119 MB `kernel_blob.bin` in the bundle. Flutter 3.44.8 stable (engine `13ffd72b2f9a`), against a different pinned CI version. Xcode 26.4 (17E192). Simulator iPhone 17 Pro, iOS 26.4, UDID `ADC756F6-25C5-4DA0-8E0C-304EA0BF3B44`. Local Supabase up and seeded. No MapTiler key and no local Protomaps server, so no basemap. Xcode build 290.7 s; whole command 6 m 44 s; exit 0.

**Rung reached: build-verified, plus sim-verified on four narrow observables.**

| # | Checked | Rung | Literal result |
|---|---|---|---|
| 1 | Runner target links for the simulator with every plugin | build-verified | Exit 0, `✓ Built build/ios/iphonesimulator/Runner.app`. Flutter named three plugins with no SPM support — `flutter_tts`, `health`, `workmanager_apple` — which fell back to CocoaPods and linked |
| 2 | `health: ^13.0.0` is a real dependency of the iOS target | build-verified | `apps/mobile_ios/pubspec.yaml:60`; `health.framework` present in the built bundle |
| 3 | The importer carries iOS branches, not Android-only code | host-tested (source) | `lib/health_connect_importer.dart` gates `HealthDataType.WORKOUT_ROUTE` (:106) and `…STEPS` (:112) on `Platform.isAndroid`, branches again at :252; `requestHealthRoutePermission` returns false off Android (:68–69) |
| 4 | Both HealthKit usage strings reached the built product | build-verified | `plutil -p Runner.app/Info.plist` → `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` |
| 5 | The HealthKit entitlement is requested | source only | `ios/Runner/Runner.entitlements` → `com.apple.developer.healthkit`. **Not** build-verified: `--no-codesign` embedded no entitlements (trap 2) |
| 6 | The Import screen renders an iOS-specific card | host-tested (source) | `lib/screens/import_screen.dart:689–691` selects `importHealthSubtitleIos` on `Platform.isIOS`; `healthLabelFor` (:948) yields "Apple Health" |
| 7 | That string is localized in every shipped catalogue | host-tested (source) | `importHealthSubtitleIos` present in all seven ARBs under `lib/l10n/` |
| 8 | App installs and cold-launches | sim-verified | Launched to the Home screen; header "Home", Today's-workout card "Recovery 5.0 km @ 5:30/km", ALL TIME "135.40 km / 20 runs" |
| 9 | Auto-login against loopback Supabase | sim-verified (debug only) | The same launch arrived **signed in** with seeded data and no sign-in screen — `.env.development` under `kDebugMode`, gated loopback-only by `shouldAutoLogin` (`lib/dev_auto_login.dart`, called once at `lib/main.dart:561–572`). Says nothing about the release sign-in path |
| 10 | Layout at the largest non-accessibility text size | sim-verified | `content_size extra-extra-extra-large`: Home renders cleanly, all five nav labels full, no overflow |
| 11 | Layout at accessibility text sizes | sim-verified | `accessibility-medium`: clean. `accessibility-extra-extra-extra-large`: **five "BOTTOM OVERFLOWED BY 12 PIXELS" banners** across the bottom nav, labels clipped to "Ho / Fit / L / So / You". See the finding below |
| 12 | The auth URL scheme resolves to the app | build-verified | `simctl openurl com.threkir.app://login-callback/?code=…` raised SpringBoard's *Open in "Threkir"?* alert. The scheme is registered; whether the callback is then handled is **untested** — the alert needs a tap |
| 13 | Route-import file types the OS will hand to the app | build-verified | `Info.plist` declares **two** — `com.topografix.gpx`, `com.google.earth.kml` — in both `CFBundleDocumentTypes` and `UTImportedTypeDeclarations`. The Dart picker offers **six**. See the finding below |
| 14 | Native plist surface of the built app | build-verified | `UIBackgroundModes` = audio, location, processing. `BGTaskSchedulerPermittedIdentifiers` = `com.threkir.backgroundSync`. Ten `NS*UsageDescription` strings. `MinimumOSVersion` 15.0 |
| 15 | Localization of the native consent prompts | build-verified | The built bundle carries **`Base.lproj` only** — no per-locale `InfoPlist.strings`. The ten usage descriptions therefore render in English in all seven shipped locales. This confirms, from the built product, what parity.md's localization row already states as open |

**Finding A — bottom nav overflows at accessibility text sizes.** At `accessibility-extra-extra-extra-large` the Home screen's bottom navigation overflows its constraint by 12 px on every one of the five destinations, and each label truncates. Measured clean at `extra-extra-extra-large` (the largest size reachable without Accessibility settings) and at `accessibility-medium`, so the failure is inside the accessibility range; the first failing step was not bisected. The Dart is the byte-identical twin, so Android is very likely affected at the equivalent scale. Reproduce with Step 4's text-size lever. Not fixed here — this file does not edit `apps/`.

**Finding B — three route-import formats have no iOS UTI.** `kmz`, `geojson` and `tcx` are in `kRouteImportPickerExtensions` and in the format dispatch, but neither `CFBundleDocumentTypes` nor `UTImportedTypeDeclarations` declares them. Two iOS-only consequences, both invisible from the shared Dart: the OS cannot offer the app under "Open with" for those files, and a `FileType.custom` document picker resolves an unmatchable dynamic UTI, which greys them out. The first half is build-verified from the bundle. The second half is a strong prediction from how `file_picker` maps extensions on iOS and **needs a hands-on check of the picker before it is claimed**.

**Not reached, and why:**

- **Every recording-stack row.** No real GNSS, no barometer, no usable Core Motion. The simulator would have produced a clean, noiseless track proving nothing about the filter chain, auto-pause, or the GPS-lost banner.
- **BLE strap and FTMS treadmill.** No radio exists on a simulator.
- **A real HealthKit import.** The store is empty and nothing seeds it without hand entry.
- **Push registration, background sync, background location, purchases.** No APNs token, no real suspension, no sandbox Apple ID.
- **Release-mode behaviour of anything.** The only build the simulator accepts is debug (trap 1).
- **Every screen past Home.** No `integration_test/` target exists and `simctl` has no tap primitive, so Steps 4's deep-link lever and the whole of Step 5 could not be driven. This is the largest gap between this pass and a real one, and it is a *tooling* gap rather than a scheduling one.
- **CI-parity toolchain.** Built on local Flutter 3.44.8, not the pinned CI version.

**Cells converted: none, which is the correct outcome.** The column moves on one line of the derivation table; that line is a claim about the whole shipped surface; and a simulator cannot reach the classes most of that surface depends on. What this run did produce is two obstruction findings, one corrected justification (the in-app-update row, below), and independent confirmation of the HealthKit row rather than its assertion.
