import Foundation
import WatchConnectivity

/// Transfers completed runs from the Apple Watch to the paired iPhone over
/// `WCSession.transferFile(_:metadata:)`. The phone owns the Supabase write —
/// the watch just hands over the JSON track file + a metadata dict.
/// WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay),
/// queues across app launches, and retries on its own. Queued transfers
/// survive app closure and watch reboot, so a day of offline runs will all
/// drain to Supabase the moment the phone companion app next activates its
/// own `WCSession`.
///
/// The same session carries the inbound direction: the phone's unit
/// preference and the route it armed for this watch to follow (`ArmedRoute`).
/// The phone's settings envelope, decoded.
///
/// Split out of `WatchConnectivityManager.receive` so the fail-closed half is
/// testable at all: the manager's `init` activates a real `WCSession`, which
/// no unit-test host can construct, and this is the only decode on the
/// inbound wire that is not already a value type of its own
/// (`ArmedRoute.decode`, `LiveRace.decode`).
///
/// Every reader answers nil for "the phone did not say", never a default. A
/// push may carry any subset — a route arrives with no preferences at all —
/// so a default here would quietly overwrite an explicit choice every time
/// the runner armed a route.
enum PhonePreferences {
    /// The UserDefaults key the unit is stored under. Spelled the same as the
    /// wire key below by design — `RunFormat` and `ActiveRunBridge` read this
    /// one, `preferredUnit(in:)` reads the wire — and pinned equal by
    /// `PhonePreferencesTests`.
    static let unitKey = "preferred_unit"

    /// `km` or `mi`, and nothing else. A rogue or future value leaves the
    /// unit the wrist already holds standing rather than falling back to
    /// kilometres: the settings envelope rides `updateApplicationContext`,
    /// which the system RETAINS and re-offers on every contact, so a coerced
    /// wrong answer would be a wrong answer on every contact.
    static func preferredUnit(in payload: [String: Any]) -> String? {
        guard let unit = payload["preferred_unit"] as? String,
              unit == "km" || unit == "mi" else { return nil }
        return unit
    }

    /// Whether the spoken cues are audible. A non-Bool is dropped rather than
    /// coerced — a corrupt push must neither silence cues nobody turned off
    /// nor un-mute an explicit off.
    static func audioCues(in payload: [String: Any]) -> Bool? {
        payload["audio_cues"] as? Bool
    }
}

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    enum TransferState: Equatable {
        case idle
        case pending
        case completed
        case failed(String)
    }

    @Published var transferState: TransferState = .idle
    @Published var queuedCount: Int = 0

    /// The route the phone last pushed, restored from disk so it survives the
    /// gap between arriving (often while the app is backgrounded) and the
    /// runner opening the app to start.
    @Published var armedRoute: ArmedRoute? = ArmedRouteStore.load()

    /// The starred routes the phone last pushed, for the pre-run picker.
    /// Restored from disk for the same reason `armedRoute` is: the push lands
    /// long before the app is on screen.
    @Published var savedRoutes: [ArmedRoute] = SavedRoutesStore.load()
    /// The race the phone last armed on this wrist, restored from disk for
    /// the same reason `armedRoute` is: the Arm push lands while the app is
    /// backgrounded and the runner opens it minutes later.
    @Published private(set) var liveRace: LiveRace?

    /// Arm / Go / End lives here rather than in `WorkoutManager` because the
    /// phone is what advances it and this is the end of that wire. The
    /// machine itself is pure and tested on its own — see `LiveRace.swift`.
    private var raceState = LiveRaceState()

    /// A ping is worthless late: a dot an hour old on a spectator map is a
    /// lie about where the runner is. So it rides `sendMessage`, which needs
    /// a reachable phone and is DROPPED when there is not one, rather than
    /// the durable queue the run hand-off uses. Injectable because `WCSession`
    /// cannot be constructed in the unit-test host.
    var sendRacePing: ([String: Any]) -> Void = { payload in
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(payload, replyHandler: nil) { error in
            debugPrint("[race] ping not delivered: \(error.localizedDescription)")
        }
    }

    /// The opposite trade to the ping: a finisher's official time must
    /// survive a dead spot, a closed app and a watch reboot, so it rides the
    /// durable `transferUserInfo` outbox — and goes to disk when even that
    /// cannot take it yet (see `PendingRaceResultStore`).
    var sendRaceResult: ([String: Any]) -> Void = { payload in
        let session = WCSession.default
        guard session.activationState == .activated else {
            PendingRaceResultStore.append(payload)
            return
        }
        session.transferUserInfo(payload)
    }

    override init() {
        super.init()
        raceState = LiveRaceState(race: LiveRaceStore.load())
        liveRace = raceState.race
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// The seam `WorkoutManager` records through. Handed over once, at
    /// `ContentView`'s `.task`, so the recorder holds no reference to this
    /// class and a race effect can only ever be given a value.
    func liveRaceRelay() -> LiveRaceRelay {
        LiveRaceRelay(
            ping: { [weak self] sample in self?.pushRacePing(sample) },
            finish: { [weak self] finish in self?.reportRaceFinish(finish) }
        )
    }

    private func pushRacePing(_ sample: RacePingSample) {
        guard let payload = raceState.ping(sample) else { return }
        sendRacePing(payload)
    }

    private func reportRaceFinish(_ finish: RaceFinish) {
        guard let payload = raceState.finish(finish) else { return }
        LiveRaceStore.clear()
        let published = raceState.race
        DispatchQueue.main.async { self.liveRace = published }
        sendRaceResult(payload)
    }

    private func applyRace(_ race: LiveRace) {
        guard raceState.apply(race) else { return }
        if let active = raceState.race {
            LiveRaceStore.save(active)
        } else {
            LiveRaceStore.clear()
        }
        let published = raceState.race
        DispatchQueue.main.async { self.liveRace = published }
    }

    /// A run may only be handed off once WCSession has finished activating.
    /// `WCSession.activate()` is async at launch, so a short run right after a
    /// cold launch (or a session gone `.inactive`) can reach the sync tap
    /// before this is true. Pure so the caller-side decision is unit-testable
    /// without constructing the manager (its `init` activates a real session).
    static func canTransfer(activationState: WCSessionActivationState) -> Bool {
        activationState == .activated
    }

    /// What the watch may say about its own outbox the moment the session
    /// finishes activating.
    ///
    /// `queuedCount` and `transferState` are in-memory, and WCSession's outbox
    /// is not: a queued transfer survives app closure AND watch reboot, and
    /// waits days for a phone that is switched off. So on every relaunch the
    /// two disagreed — the watch came up saying `.idle` with a count of zero
    /// while the platform was still holding runs, and the pre-run screen's
    /// "N run queued to sync" line, the only place the watch ever says a run is
    /// still waiting, was simply absent (decisions § 1209).
    ///
    /// Pure because `WCSession` cannot be constructed in the unit-test host —
    /// the same reason `canTransfer` above is pure.
    static func stateOnActivation(outstanding: Int) -> TransferState {
        outstanding > 0 ? .pending : .idle
    }

    /// Hand a finished run off to the phone. Returns `true` only when the file
    /// was handed to WCSession's outbox (queued for delivery); `false` when the
    /// session isn't activated yet and nothing was queued. A `false` MUST be
    /// read by the caller as "not synced" — the finished run has to be kept for
    /// a retry, never marked done, or it is silently and irrecoverably dropped.
    func transferRun(fileURL: URL, metadata: [String: Any]) -> Bool {
        guard Self.canTransfer(activationState: WCSession.default.activationState) else {
            let message = String(localized: "Phone unavailable — tap Sync Run to retry")
            DispatchQueue.main.async { self.transferState = .failed(message) }
            return false
        }
        WCSession.default.transferFile(fileURL, metadata: metadata)
        DispatchQueue.main.async {
            // Read off the platform rather than incremented: the outbox
            // already holds the transfer just handed to it, and a private
            // tally seeded at zero on every launch is what made the count a
            // claim about this app session rather than about the queue.
            self.queuedCount = WCSession.default.outstandingFileTransfers.count
            self.transferState = .pending
        }
        return true
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard Self.canTransfer(activationState: activationState) else { return }
        let outstanding = session.outstandingFileTransfers.count
        DispatchQueue.main.async {
            self.queuedCount = outstanding
            self.transferState = Self.stateOnActivation(outstanding: outstanding)
        }
        // The settings the phone last wrote, which the platform retains for
        // us. Nothing calls `didReceiveApplicationContext` for a value that
        // arrived before this process existed, so without this a cold launch
        // reads whatever UserDefaults held — which on a watch that spent the
        // change on a charger is the value the runner replaced.
        let context = session.receivedApplicationContext
        if !context.isEmpty { receive(context) }
        // A finisher time that ended up on disk because the session was not
        // activated yet. Auxiliary, and kept out of the run outbox's own
        // re-seed above: a race result that will not send must not cost the
        // count of runs that are still waiting.
        for payload in PendingRaceResultStore.drain() {
            session.transferUserInfo(payload)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil {
            // Only now is the run somewhere other than this watch. Deleting
            // the export any earlier — at reset(), say — would pull the file
            // out from under a transfer WCSession is still reading.
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
        DispatchQueue.main.async {
            if self.queuedCount > 0 { self.queuedCount -= 1 }
            if let error = error {
                self.transferState = .failed(error.localizedDescription)
            } else if self.queuedCount == 0 {
                self.transferState = .completed
            }
        }
    }

    /// Files WCSession is still holding for delivery. Survives app launches,
    /// so it is the authoritative keep-set for the stale-export sweep.
    func pendingTransferURLs() -> Set<URL> {
        guard WCSession.isSupported() else { return [] }
        return Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL })
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    // Also handle the alternative `userInfo` transport (queued, durable
    // across watch reboots). The phone may push via either sendMessage
    // (when the watch is reachable) or transferUserInfo (queues until the
    // watch wakes), so honour both. Routes always arrive this way — the
    // phone has no reason to expect a reachable watch when the runner
    // picks a route.
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        receive(userInfo)
    }

    /// The phone's settings envelope. `updateApplicationContext` is a single
    /// latest-value slot rather than a queue, which is the right shape for a
    /// preference and the wrong one for a run: the phone overwrites it on
    /// every change, so a week of toggling costs one delivery and the wrist
    /// gets the CURRENT answer on its next contact instead of replaying every
    /// intermediate one. A `sendMessage` would have dropped them all while
    /// the watch was out of range, which is exactly the hole this closes.
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        receive(applicationContext)
    }

    /// Apply whatever the phone put in a payload. Every key is independent:
    /// a payload carrying only one of them leaves the rest untouched.
    private func receive(_ payload: [String: Any]) {
        // `preferred_unit` — the user's distance preference on the
        // phone (`'km'` or `'mi'`). Stored in UserDefaults so the
        // pre-run pace presets (see `pacePresets()` in
        // ContentView.swift) and any other unit-sensitive surface can
        // read it synchronously without a `@Published` observation.
        // Pushed by `AppleWatchPrefsBridge` on the phone whenever the
        // runner changes it — including when the change came from the
        // web settings page and roamed in over `SettingsSyncService`.
        if let unit = PhonePreferences.preferredUnit(in: payload) {
            UserDefaults.standard.set(unit, forKey: PhonePreferences.unitKey)
            ActiveRunBridge.mirrorPreferredUnit(unit)
        }
        // `audio_cues` — whether the spoken split / pace cues are audible
        // (`RunAnnouncer.preferenceKey`). Rides the same envelope as the unit
        // above, and is the ONLY way a runner can silence the wrist: the
        // watch app has no settings screen. Absent still means ON, which is
        // the phone's default, so the key only ever arrives to turn cues OFF
        // or back on — and a non-Bool is dropped rather than coerced, because
        // a corrupt push must neither silence cues nobody turned off nor
        // un-mute an explicit off.
        if let cues = PhonePreferences.audioCues(in: payload) {
            UserDefaults.standard.set(cues, forKey: RunAnnouncer.preferenceKey)
        }
        // A malformed or over-budget route is dropped whole rather than
        // trimmed — see `ArmedRoute.decode`. Persist before publishing so a
        // route that arrives while the app is backgrounded is still there
        // when the runner next opens it.
        if let route = ArmedRoute.decode(payload) {
            ArmedRouteStore.save(route)
            DispatchQueue.main.async { self.armedRoute = route }
        }
        // The picker's list of starred routes. Independent of the armed
        // route above — a push may carry either, both or neither — and an
        // empty array is the runner having unstarred their last one, so it
        // empties the picker rather than being read as "nothing sent".
        if let routes = SavedRoutes.decodeList(payload) {
            SavedRoutesStore.save(routes)
            DispatchQueue.main.async { self.savedRoutes = routes }
        }
        // Arm / Go / End. Fail-closed the same way: a status word this build
        // does not know leaves the wrist where it was, rather than clearing a
        // race that is still running.
        if let race = LiveRace.decode(payload) {
            applyRace(race)
        }
    }

    /// Arm a route the runner picked on the wrist. Writes through
    /// `ArmedRouteStore` rather than only publishing, because
    /// `WorkoutManager.start()` reads the route off disk and not off this
    /// object.
    func armRoute(_ route: ArmedRoute) {
        ArmedRouteStore.save(route)
        armedRoute = route
    }

    /// Drop the armed route from the wrist. The phone is the only writer, so
    /// without this the runner's only way out of a route they no longer want
    /// is to go back to the phone.
    func clearArmedRoute() {
        ArmedRouteStore.clear()
        armedRoute = nil
    }
}
