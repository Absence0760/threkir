# Active-run complication — the `WatchAppComplication` target

The complication ships as a watchOS **Widget Extension** target inside
`WatchApp.xcodeproj`, embedded in `WatchApp.app/PlugIns/`. It is a real target
in the committed `project.pbxproj`, not a manual Xcode step: `xcodebuild build
-scheme WatchApp` compiles `ActiveRunComplication.swift`, and `xcodebuild test`
compiles it too, because `WatchAppTests` hosts on `WatchApp` and `WatchApp`
depends on the extension.

## What is in the target

| Object | Value |
|---|---|
| Target | `WatchAppComplication`, product type `com.apple.product-type.app-extension` |
| Product | `WatchAppComplication.appex`, copied into `$(CONTENTS_FOLDER_PATH)/PlugIns` by the `Embed Foundation Extensions` phase on `WatchApp` |
| Bundle id | `com.threkir.app.watchapp.complication` |
| Info.plist | `Complications/Info.plist` (`GENERATE_INFOPLIST_FILE = NO`), declaring `NSExtensionPointIdentifier = com.apple.widgetkit-extension` |
| Entitlements | `Complications/WatchAppComplication.entitlements`, carrying the one App Group `group.com.threkir.app.activerun` |
| Sources | `Complications/ActiveRunComplication.swift`, plus three files that are members of **both** targets: `Complications/ActiveRunTimeline.swift`, `WatchApp/ActiveRunBridge.swift`, `WatchApp/RunFormat.swift` |
| Resources | `WatchApp/Localizable.xcstrings` (a member of both targets) |
| Frameworks | `WidgetKit`, `SwiftUI` |
| Deployment | watchOS 10.0, `TARGETED_DEVICE_FAMILY = 4`, same as the host |

The App Group identifier must stay identical to `ActiveRunBridge.appGroup`; a
shared container bound under a different name yields no store and reports
nothing. `scripts/check_watch_ios_source.mjs` claim (5) holds this README
against the constant.

## The catalogue has to be in the extension's own bundle

`Localizable.xcstrings` is a Resources member of **both** targets on purpose. A
widget extension localises against its own bundle, so without the second
membership `Text("RUN")`, `Text("Tap to start")` and
`.configurationDisplayName("Active Run")` would render English on every wrist
while the host app localised correctly — the silent shape § 884 is about.
Verified from the built product: `WatchAppComplication.appex/de.lproj/Localizable.strings`
contains `"Active Run" => "Aktiver Lauf"`.

The extension's `Info.plist` deliberately carries **no** `CFBundleLocalizations`
array, unlike the host app's. The bundle's available localisations are then the
`.lproj` directories the compiled catalogue actually produced, which is derived
rather than transcribed — a hand-written list here would be a second place for
the locale set to drift, and nothing reads it.

## `statLine(_:)` and the non-localising overload

§ 884 removed two `LocalizedStringKey` lookups for `%@ · %@` by routing both
through `private func statLine(_:) -> String`, on the reading that a `String`
argument selects `Text`/`Label`'s non-localising `StringProtocol` overload. That
reading is now checked by the compiler rather than asserted: the target sets
`SWIFT_EMIT_LOC_STRINGS = YES`, so
`…/WatchAppComplication.build/Objects-normal/arm64/ActiveRunComplication.stringsdata`
is the compiler's own list of every literal it extracted as localisable. It
holds 11 keys, all of them already in the catalogue, and **no** `%@ · %@` — the
`Label(statLine(entry), …)` and `Text(statLine(entry))` call sites do not appear
in it at all, while the `Label("Tap to start", …)` three lines below does.

That file is the thing to look at if this ever regresses: a key appearing there
that the catalogue does not carry is a string that will be English on six
wrists, and `check_xcstrings_parity.sh` will not see it until Xcode writes it
into `Localizable.xcstrings`.

## What the extension's own tests reach, and what they cannot

There is one copy of each formatter. `WatchApp/RunFormat.swift` and
`Complications/ActiveRunTimeline.swift` are members of the extension AND of
`WatchApp`, so `WatchAppTests` — which `@testable import WatchApp` — exercises
the same source the watch face runs. `WatchAppComplication` has no test host of
its own and cannot have one; making the testable logic a member of a target
that already has a test host is the mechanism, and it is the same one
`ActiveRunBridge.swift` has always used.

`ActiveRunComplication.swift` itself stays outside that: it declares the
`@main` widget bundle, a module may hold only one, and `WatchApp` has its own.
So the split is deliberate — everything decidable without WidgetKit's runtime
(the staleness ceiling, the timeline cadence, the composed stat line, the three
formatters) lives in `ActiveRunTimeline.swift` and is covered by
`WatchAppTests/ActiveRunComplicationTests.swift`; the views, the
`supportedFamilies` list and the widget's `kind` are compiled on every PR and
run by nothing.

The duplication this replaced was held byte-identical by claim (4) of
`scripts/check_watch_ios_source.mjs`, which is retired: with one copy the drift
it watched for has nowhere to happen, and dropping a shared file from one
target's membership is a missing symbol — a compile error in whichever project
dropped it, not a silent divergence. Claim (15) now compares the
`WatchAppComplication` membership lists of `WatchApp.xcodeproj` and
`Runner.xcodeproj` against each other, the way it already did the app's.

## How it ties together at runtime

```
WorkoutManager (host app)
  ├─ start / pause / resume / stop / reset
  └─ publishComplicationSnapshot()
        ├─ ActiveRunBridge.write(snapshot)            ── App Group UserDefaults
        └─ WidgetCenter.reloadTimelines(ofKind: ...)  ── nudges the OS

ActiveRunProvider (widget extension)
  └─ getTimeline()
        └─ ActiveRunBridge.read()                     ── reads same UserDefaults
              └─ ActiveRunEntryView                   ── renders for current widgetFamily
```

The kind is `ActiveRunBridge.complicationKind`, read by both targets rather than
spelled twice: `reloadTimelines(ofKind:)` with a kind no widget declares is a
silent no-op, so a rename on one side alone would leave the watch face showing
the pre-run state for up to ~30 minutes into a run with nothing reporting it.

The complication doesn't poll — every meaningful change comes from the host
app's `publishComplicationSnapshot`. Per-tick GPS deltas aren't pushed; the
timeline holds 10 entries 30 s apart so the elapsed-time string ticks up between
explicit reloads without burning the platform's complication-refresh budget.

## What a device still owes

Nothing here has been seen on a watch face. `simctl` offers no way to add a
complication to a face, so "the complication appears under *Active Run* in the
face customisation UI and renders the live numbers" is unverified — the build
puts a valid `.appex` in `PlugIns/` with the right extension point (confirmed
from both projects), the pure layer behind it is unit-tested, and that is all
that has been established. This is *build-verified* plus *host-tested* on the
shared layer, never *bench-verified*; see
`docs/custom_watch/quality_standards.md`.

The km/mi preference is read through `ActiveRunBridge.prefersMiles()`, which
takes `preferred_unit` from the App Group suite the two targets share and falls
back to `UserDefaults.standard`. `UserDefaults.standard` alone was the bug: in
an extension it is the **extension's** defaults, so a runner who chose miles saw
kilometres on the watch face. That the mirror write actually reaches the
extension's process is the one part of this still unverified on a device.

## Symmetry with Wear OS

The Wear OS tile (`apps/watch_wear/.../tiles/ActiveRunTileService.kt`) ships the
same shape: idle ↔ active, the same three numbers, the same formatting (km /
min:ss/km, `formatElapsed` mirrored verbatim). When the wording or layout changes
on one platform, the other follows in the same PR — see `docs/product/parity.md`.
