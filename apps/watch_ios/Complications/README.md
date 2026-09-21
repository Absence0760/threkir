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
| Sources | `Complications/ActiveRunComplication.swift`, `WatchApp/ActiveRunBridge.swift` (the bridge is a member of both targets) |
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

## The two copies of the formatters

`ActiveRunComplication.swift` carries its own `formatElapsed` /
`formatDistanceKm` / `formatPaceSecPerKm`, byte-identical to
`WatchApp/RunFormat.swift`'s, held so by `scripts/check_watch_ios_source.mjs`
claim (4). The original reason — "a separate target cannot link
`RunFormat.swift`" — is not true: `ActiveRunBridge.swift` is a member of both
targets and demonstrates the alternative. Collapsing the two to one shared
member is the durable fix and is a separate change, because it retires claim (4)
and the `ComplicationFormatterTests` suite along with the duplicate.

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
puts a valid `.appex` in `PlugIns/` with the right extension point, and that is
all that has been established.

`formatDistanceKm` and `formatPaceSecPerKm` read `preferred_unit` from
`UserDefaults.standard`, which in an extension is the **extension's** defaults,
not the host app's. A runner who chose miles will see kilometres on the watch
face. Fixing it means carrying the unit in the snapshot (or writing the
preference to the App Group suite) — both are changes to `ActiveRunBridge` and
its writer, not to this directory.

## Symmetry with Wear OS

The Wear OS tile (`apps/watch_wear/.../tiles/ActiveRunTileService.kt`) ships the
same shape: idle ↔ active, the same three numbers, the same formatting (km /
min:ss/km, `formatElapsed` mirrored verbatim). When the wording or layout changes
on one platform, the other follows in the same PR — see `docs/product/parity.md`.
