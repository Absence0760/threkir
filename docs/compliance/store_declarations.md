# Store-console declarations

[`store_declarations.json`](store_declarations.json) is the one place the repo writes down what the Google Play Console and App Store Connect declare about the apps, and [`scripts/check_store_declarations.mjs`](../../scripts/check_store_declarations.mjs) checks it against what the shipped code requests. Decisions § 2543.

It exists because Play refused `watch_wear@1.1.0` with HTTP 403 "You must let us know whether your app uses any Foreground Service permissions". The watch's `RunRecordingService` declares `foregroundServiceType="location|health"`. Since #1380 the watch ships in the phone's Play record, `com.threkir.app`, and that record's console had only ever declared `location`. Nothing in the repo knew what the console held, so the store found the drift. A declaration that does not match the binary can get a release rejected or the app removed.

## The two store records

| Store | Record | Ships | Code read |
|---|---|---|---|
| Google Play | `com.threkir.app` | phone (`apps/mobile_android`) and Wear OS (`apps/watch_wear`) as two form factors of one listing | each app's `src/main/AndroidManifest.xml`; the phone's `res/xml/health_permissions.xml` |
| App Store | `com.threkir.app` | iPhone (`apps/mobile_ios`: Runner, RunActivity, ShareExtension) and Apple Watch (`apps/watch_ios`: WatchApp, Complications) | every bundle's `Info.plist` and `PrivacyInfo.xcprivacy`; the iPhone's HealthKit request in `lib/health_connect_importer.dart`; the watch's HealthKit types in `WatchApp/*.swift` |

The debug and profile manifests of `mobile_android` never reach a store build and are listed as unshipped in the script. A new manifest or a new bundle fails the guard until it is added to the script's source lists, so a new target cannot ship unread.

## What each category records

| Category | Key | Derived from | Console form |
|---|---|---|---|
| `android_permissions` | full permission name | `<uses-permission>`, minus `tools:node="remove"` | the form for a sensitive permission (background location, battery-optimization exemption, body sensors), or `null` for one with no form |
| `foreground_service_types` | service type | `<service android:foregroundServiceType>` | App content → Foreground service permissions |
| `health_connect` | data type (`READ_STEPS`) | `android.permission.health.*`, which must equal `health_permissions.xml` | App content → Health apps |
| `data_safety` | Play data type | not derivable; every App Privacy type must have one here (`apple_equivalent`), since the phones share one Dart codebase | App content → Data safety |
| `usage_descriptions` | Info.plist key | every `*UsageDescription*` key | none (App Review reads the binary) |
| `background_modes` | mode | `UIBackgroundModes` and `WKBackgroundModes` | App Review Information notes |
| `healthkit_types` | `health` plugin name (`HEART_RATE`) | the iPhone's request list minus `Platform.isAndroid` entries; the watch's `HK*Type` uses | App Privacy (Health & Fitness) |
| `required_reason_apis` | `Category:reason` | `NSPrivacyAccessedAPITypes` | none (checked at upload) |
| `app_privacy_label` | collected type (`PreciseLocation`) | `NSPrivacyCollectedDataTypes` | App Privacy |

Each entry has `in` (the targets that request it), `form`, `status`, and `evidence` (or `note` when there is no form). `console_only` lists something the console may still declare that the code no longer requests, for the owner to remove.

The guard also fails a privacy manifest that declares tracking: nothing here tracks, and turning that on is an owner decision with an App Tracking Transparency prompt, not a manifest edit.

### Statuses

- `declared` — the console holds it. `verified_on` dates the record that proves it (an issue checkpoint, a ticked owner step). An entry without `verified_on` is an inference, and its evidence says from what.
- `pending` — known to be missing and being added now.
- `unknown` — nobody has recorded what the console holds. Never write `declared` from memory or because it seems likely: use `unknown` and ask the owner to look.
- `not_required` — no console form exists (`form: null`). The entry is still listed, so a new permission is classified rather than missed.

The guard prints every `pending` and `unknown` entry as `[OWNER TO CONFIRM]` without failing. Those are the console checks to do before the next store release.

## When the guard fires

**The console comes first, then the registry.** The guard's `[FAIL]` line names the source file, the target and the console form.

1. **The code requests something new.** Declare it in the named console form, then add the entry (or the target to its `in`) with `status: declared`, today's `verified_on` and the evidence. If the console step is still to do, land the entry as `pending` and don't tag a release until it is done.
2. **A registry entry is stale.** Remove the declaration from the console if nothing else in the record needs it, then drop the target from `in` (or delete the entry).

### Play only offers a new type after a bundle carries it

Play Console shows a new foreground service type, or another permission's declaration question, only once a bundle containing it has been uploaded. The release workflow's API upload is the thing Play refuses for the missing declaration, so neither can come first on its own. The order that works:

1. Upload the signed AAB attached to the GitHub Release by hand: Play Console → Test and release → the track (for Wear OS, the Wear OS internal track) → Create release. Save it. It doesn't need to roll out.
2. Play Console → Policy and programs → App content → the declaration it now asks for. Save.
3. Re-run the release job.

`scripts/play_release.mjs` prints these steps when Play's 403 names a declaration, rather than its service-account hint.

## What it cannot see

- **Plugin-merged manifest entries.** Gradle merges each Flutter plugin's `AndroidManifest.xml` into the phone app at build time, so the merged manifest exists only after a build. The registry lists the plugin-contributed permissions found in the locked plugin versions (`ACCESS_NETWORK_STATE` from `connectivity_plus` and `firebase_messaging`, `BLUETOOTH` and `BLUETOOTH_ADMIN` from `reactive_ble_mobile`, and others the app also declares itself) under each entry's `plugins`. The guard only holds that each named plugin is still in `pubspec.lock`. When a plugin upgrade could add a permission, read the plugin's `android/src/main/AndroidManifest.xml` in the pub cache, or `build/app/intermediates/merged_manifests/` after a build. The Wear app's AndroidX and Play services libraries can merge in entries the same way. A release AAB's merged manifest is authoritative: `bundletool dump manifest --bundle=<aab>`.
- **Data safety answers.** The form's data types aren't derivable from code. The guard only holds that every App Privacy type has a Play counterpart.
- **The consoles themselves.** No API reads them here. A `declared` status is only as good as its evidence.
