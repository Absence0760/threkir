import Flutter
import Foundation
import WatchConnectivity

/// Receives finished runs from the paired Apple Watch via
/// `WCSession.transferFile(_:metadata:)` and forwards them to Dart via
/// the `run_app/watch_ingest` method channel, and carries the opposite
/// direction — a route the runner picked on the phone, pushed to the watch
/// over `run_app/watch_route`.
///
/// Both directions live here because `WCSession.delegate` is a single slot:
/// a second class claiming its own session would take this one's delegate
/// away and silently stop run ingest.
///
/// The singleton is installed in `AppDelegate` at launch (so the
/// delegate is live before the Flutter engine exists) and the method
/// channel is attached as soon as the engine spins up. Any runs that
/// arrive before the engine is ready are queued in memory and flushed
/// when the channel becomes available.
@objc class WatchIngestBridge: NSObject, WCSessionDelegate {
    @objc static let shared = WatchIngestBridge()

    /// Positions one route push may carry. Must match `ArmedRoute.maxPoints`
    /// in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
    /// `kMaxAppleWatchRoutePoints` in `apple_watch_route_bridge.dart` — the
    /// watch drops an over-cap payload whole, so a phone that queued one
    /// would burn a durable transfer on a route that can never land.
    static let maxRoutePoints = 512

    /// Routes one picker-list push may offer, and positions one of them may
    /// carry. Must match `SavedRoutes.maxRoutes` / `SavedRoutes.maxPointsPerRoute`
    /// in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
    /// `kMaxAppleWatchSavedRoutes` / `kMaxAppleWatchSavedRoutePoints` in
    /// `apple_watch_route_bridge.dart`. `scripts/check_shared_constants.mjs`
    /// reads all three rails, so these are not a transcription of the watch's
    /// numbers — they are held against them.
    ///
    /// A quarter of `maxRoutePoints` per route because twelve ride in one
    /// 65,536-byte user-info payload where an armed route rides alone.
    static let maxSavedRoutes = 12
    static let maxSavedRoutePoints = 128

    /// A run Dart keeps refusing is re-dispatched on every watch contact, so
    /// without a ceiling a permanently-failing payload would spend a dispatch
    /// per activation and per received file for the life of the process. Past
    /// the ceiling the runs stay buffered — dropping them is the worse failure
    /// — and retrying resumes when a fresh engine attaches.
    static let maxRefusedRetries = 8

    /// Finisher times held here while no Flutter engine can take them. Matches
    /// `PendingRaceResultStore.maxEntries` on the watch and
    /// `kPendingRaceResultsMax` in `race_controller.dart`: one row per race, so
    /// the cap only exists so a permanently-failing hand-off cannot grow the
    /// buffer without limit. Oldest drop first.
    static let maxPendingRaceResults = 20

    /// `pending` and the ingest channel are touched from three queues: the
    /// WCSession delegate queue, the main queue, and the method channel's reply
    /// callback. Unsynchronised access to an `Array` across queues corrupts it.
    private let state = DispatchQueue(label: "com.threkir.watch-ingest.state")
    private var _methodChannel: FlutterMethodChannel?
    private var _pending: [[String: Any]] = []
    private var _refusedRetries = 0

    private var routeChannel: FlutterMethodChannel?
    private var _raceChannel: FlutterMethodChannel?
    private var _pendingRaceResults: [[String: Any]] = []
    private var _raceResultRetries = 0

    private var raceChannel: FlutterMethodChannel? {
        state.sync { _raceChannel }
    }

    private var methodChannel: FlutterMethodChannel? {
        state.sync { _methodChannel }
    }

    var pending: [[String: Any]] {
        get { state.sync { _pending } }
        set { state.sync { _pending = newValue } }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @objc func attach(binaryMessenger: FlutterBinaryMessenger) {
        let ingest = FlutterMethodChannel(
            name: "run_app/watch_ingest",
            binaryMessenger: binaryMessenger
        )
        let routes = FlutterMethodChannel(
            name: "run_app/watch_route",
            binaryMessenger: binaryMessenger
        )
        // Strong capture: `shared` is a permanent singleton, so there is no
        // cycle to break — and a weak self going nil would leave the Dart
        // future unanswered forever instead of failing.
        routes.setMethodCallHandler { call, result in
            self.handleRouteCall(call, result: result)
        }
        routeChannel = routes
        // One channel, both directions: Dart invokes `push` on it and this
        // class invokes `racePing` / `raceResult` back down it.
        let race = FlutterMethodChannel(
            name: "run_app/watch_race",
            binaryMessenger: binaryMessenger
        )
        race.setMethodCallHandler { call, result in
            self.handleRaceCall(call, result: result)
        }
        state.sync {
            _methodChannel = ingest
            _raceChannel = race
            // A fresh engine is a genuinely new chance at the write, so a run
            // stranded by the retry ceiling gets tried again rather than
            // sitting in the buffer until the process dies.
            _refusedRetries = 0
            _raceResultRetries = 0
        }
        flushPending()
        flushPendingRaceResults()
    }

    // MARK: - Live race relay (phone <-> watch)

    /// Arm / Go / End, phone to wrist. `transferUserInfo` for the reason the
    /// route push uses it and with one more at stake: the Arm lands while the
    /// watch is on a charger in another room, and nothing on the watch times a
    /// live race out, so an End that is merely *sent* leaves `RACE LIVE` on the
    /// wrist forever (decisions § 1697).
    private func handleRaceCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "push":
            guard let args = call.arguments as? [String: Any],
                  let payload = Self.raceUserInfo(from: args) else {
                result(FlutterError(
                    code: "bad_race",
                    message: "Race payload rejected",
                    details: nil
                ))
                return
            }
            guard Self.canPushRoute() else {
                result(FlutterError(
                    code: "watch_unavailable",
                    message: "No paired Apple Watch running the app",
                    details: nil
                ))
                return
            }
            WCSession.default.transferUserInfo(payload)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Re-check the shape here as well as in Dart, for the reason
    /// `routeUserInfo` does: a payload that reaches `transferUserInfo` is
    /// queued durably and retried against a watch that will refuse it every
    /// time. `LiveRace.decode` is the other end of this list.
    static func raceUserInfo(from args: [String: Any]) -> [String: Any]? {
        guard let eventId = args["race_event_id"] as? String, !eventId.isEmpty,
              let instanceStart = args["race_instance_start"] as? String,
              !instanceStart.isEmpty,
              let status = args["race_status"] as? String,
              ["armed", "running", "finished", "cancelled"].contains(status)
        else { return nil }
        var payload: [String: Any] = [
            "race_event_id": eventId,
            "race_instance_start": instanceStart,
            "race_status": status,
        ]
        if let title = args["race_event_title"] as? String, !title.isEmpty {
            payload["race_event_title"] = title
        }
        return payload
    }

    /// One relayed fix, or nil when the message carries none this build will
    /// act on. Fail-closed like `routeUserInfo`: a half-read ping would put
    /// the runner somewhere they have not been on a map other people read.
    static func racePingPayload(from message: [String: Any]) -> [String: Any]? {
        guard let eventId = message["race_ping_event_id"] as? String, !eventId.isEmpty,
              let instanceStart = message["race_ping_instance_start"] as? String,
              !instanceStart.isEmpty,
              let latitude = message["race_ping_lat"] as? Double, latitude.isFinite,
              let longitude = message["race_ping_lng"] as? Double, longitude.isFinite
        else { return nil }
        var payload: [String: Any] = [
            "race_ping_event_id": eventId,
            "race_ping_instance_start": instanceStart,
            "race_ping_lat": latitude,
            "race_ping_lng": longitude,
        ]
        if let distance = message["race_ping_distance_m"] as? Double,
           distance.isFinite, distance >= 0 {
            payload["race_ping_distance_m"] = distance
        }
        if let elapsed = message["race_ping_elapsed_s"] as? Int, elapsed >= 0 {
            payload["race_ping_elapsed_s"] = elapsed
        }
        if let bpm = message["race_ping_bpm"] as? Int, bpm > 0 {
            payload["race_ping_bpm"] = bpm
        }
        return payload
    }

    /// One relayed finisher time, or nil when the transfer carries none.
    static func raceResultPayload(from userInfo: [String: Any]) -> [String: Any]? {
        guard let eventId = userInfo["race_result_event_id"] as? String, !eventId.isEmpty,
              let instanceStart = userInfo["race_result_instance_start"] as? String,
              !instanceStart.isEmpty,
              let runId = userInfo["race_result_run_id"] as? String, !runId.isEmpty,
              let duration = userInfo["race_result_duration_s"] as? Int, duration >= 0,
              let distance = userInfo["race_result_distance_m"] as? Double,
              distance.isFinite, distance >= 0
        else { return nil }
        return [
            "race_result_event_id": eventId,
            "race_result_instance_start": instanceStart,
            "race_result_run_id": runId,
            "race_result_duration_s": duration,
            "race_result_distance_m": distance,
        ]
    }

    /// A ping the engine cannot take right now is DROPPED, never buffered.
    /// That is the whole trade the watch made when it sent this over
    /// `sendMessage` instead of the durable outbox: a position delivered an
    /// hour late is a lie about where the runner is, and buffering here would
    /// re-introduce exactly the stale dot the watch refused to queue.
    func dispatchRacePing(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.raceChannel?.invokeMethod("racePing", arguments: payload)
        }
    }

    /// The opposite trade: a finisher's official time is the one value in the
    /// feature nobody can re-derive, so it waits for an engine rather than
    /// being dropped, and a Dart `false` puts it back.
    func dispatchRaceResult(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let channel = self.raceChannel else {
                self.bufferRaceResult(payload)
                return
            }
            channel.invokeMethod("raceResult", arguments: payload) { [weak self] result in
                if let ok = result as? Bool, !ok {
                    self?.requeueRefusedRaceResult(payload)
                }
            }
        }
    }

    func flushPendingRaceResults() {
        let snapshot = state.sync { () -> [[String: Any]] in
            guard _raceResultRetries < Self.maxPendingRaceResults else { return [] }
            let snapshot = _pendingRaceResults
            _pendingRaceResults.removeAll()
            return snapshot
        }
        for payload in snapshot { dispatchRaceResult(payload) }
    }

    private func bufferRaceResult(_ payload: [String: Any]) {
        state.sync {
            _pendingRaceResults.append(payload)
            if _pendingRaceResults.count > Self.maxPendingRaceResults {
                _pendingRaceResults.removeFirst(
                    _pendingRaceResults.count - Self.maxPendingRaceResults
                )
            }
        }
    }

    func requeueRefusedRaceResult(_ payload: [String: Any]) {
        state.sync { _raceResultRetries += 1 }
        bufferRaceResult(payload)
    }

    // MARK: - Route push (phone -> watch)

    /// `transferUserInfo`, not `sendMessage`: the runner picks a route while
    /// the watch is on a charger in another room, so the push has to outlive
    /// an unreachable counterpart. WCSession queues user-info transfers
    /// across app launches and watch reboots and delivers them in order,
    /// waking the watch app in the background to hand them over.
    private func handleRouteCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "available":
            result(Self.canPushRoute())
        case "push":
            guard let args = call.arguments as? [String: Any],
                  let payload = Self.routeUserInfo(from: args) else {
                result(FlutterError(
                    code: "bad_route",
                    message: "Route payload rejected",
                    details: nil
                ))
                return
            }
            guard Self.canPushRoute() else {
                result(FlutterError(
                    code: "watch_unavailable",
                    message: "No paired Apple Watch running the app",
                    details: nil
                ))
                return
            }
            WCSession.default.transferUserInfo(payload)
            result(nil)
        case "push_saved":
            guard let args = call.arguments as? [String: Any],
                  let payload = Self.savedRoutesUserInfo(from: args) else {
                result(FlutterError(
                    code: "bad_saved_routes",
                    message: "Saved-route list rejected",
                    details: nil
                ))
                return
            }
            guard Self.canPushRoute() else {
                result(FlutterError(
                    code: "watch_unavailable",
                    message: "No paired Apple Watch running the app",
                    details: nil
                ))
                return
            }
            WCSession.default.transferUserInfo(payload)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func canPushRoute() -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    /// Re-check the shape here as well as on the watch. A malformed payload
    /// that reaches `transferUserInfo` is queued durably and retried by the
    /// system forever against a watch that will reject it every time; the
    /// runner sees a success they never got.
    static func routeUserInfo(from args: [String: Any]) -> [String: Any]? {
        guard let id = args["route_id"] as? String, !id.isEmpty,
              let name = args["route_name"] as? String,
              let distance = args["route_distance_m"] as? Double,
              distance.isFinite, distance >= 0,
              let latitudes = args["route_lat"] as? [Double],
              let longitudes = args["route_lng"] as? [Double],
              latitudes.count == longitudes.count,
              latitudes.count >= 2, latitudes.count <= maxRoutePoints
        else { return nil }
        return [
            "route_id": id,
            "route_name": name,
            "route_distance_m": distance,
            "route_lat": latitudes,
            "route_lng": longitudes,
        ]
    }

    /// Repack the wrist picker's starred list for `transferUserInfo`.
    ///
    /// Every element goes through `routeUserInfo(from:)` — the SAME validator
    /// a single armed push takes — so the list can never carry a dictionary
    /// `ArmedRoute.decode` would refuse, and picking one on the wrist is a
    /// store write rather than a second decode with a second set of rules.
    /// It is also why there is no second key list here to drift from that one.
    ///
    /// An element that fails, or that overruns `maxSavedRoutePoints`, is
    /// dropped and the rest of the list stands. Deliberately weaker than the
    /// single push's drop-the-whole-thing rule, whose reason does not reach
    /// here: there a rejection would leave a PARTLY decoded polyline and
    /// measure the runner against a line their route does not have, where each
    /// element of a list is whole or absent on its own. What is preserved is
    /// that nothing reaches the picker the watch could not follow — arming it
    /// would fail at the start of the run instead.
    ///
    /// An EMPTY array is a value rather than an absence: it is what lands when
    /// the runner unstars their last route, and it must empty the picker. So
    /// the only rejection of the whole payload is a missing `saved_routes`.
    static func savedRoutesUserInfo(from args: [String: Any]) -> [String: Any]? {
        guard let raw = args["saved_routes"] as? [[String: Any]] else { return nil }
        var routes: [[String: Any]] = []
        routes.reserveCapacity(min(raw.count, maxSavedRoutes))
        for element in raw {
            guard let route = routeUserInfo(from: element) else { continue }
            guard let latitudes = route["route_lat"] as? [Double],
                  latitudes.count <= maxSavedRoutePoints
            else { continue }
            routes.append(route)
            if routes.count == maxSavedRoutes { break }
        }
        return ["saved_routes": routes]
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        flushPending()
        flushPendingRaceResults()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let payload = Self.racePingPayload(from: message) else { return }
        dispatchRacePing(payload)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = Self.raceResultPayload(from: userInfo) else { return }
        dispatchRaceResult(payload)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required by the protocol on iOS; reactivate so the session
        // keeps working if the user switches paired watches.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Watch contact is the retry trigger: a run Dart refused earlier gets
        // another go here, ahead of the one just handed over, so the buffer
        // drains in arrival order instead of waiting for an engine re-attach.
        flushPending()
        guard let metadata = file.metadata else { return }

        // The file itself is the raw JSON array of track points the
        // watch wrote. Forward it as a string and let the Dart side
        // decode. `FileManager`-based read because the file URL is a
        // temporary inbox location we may lose access to momentarily.
        var track = "[]"
        if let data = try? Data(contentsOf: file.fileURL),
           let str = String(data: data, encoding: .utf8) {
            track = str
        }

        let payload = Self.ingestPayload(metadata: metadata, track: track)
        let engineIsUp = state.sync { () -> Bool in
            guard _methodChannel != nil else {
                _pending.append(payload)
                return false
            }
            return true
        }
        if engineIsUp { dispatch(payload) }
    }

    static func ingestPayload(metadata: [String: Any], track: String) -> [String: Any] {
        var payload: [String: Any] = [:]
        // Required metadata fields — match what watch_ios writes in
        // `ContentView.syncRun()`.
        for key in ["id", "started_at", "source", "activity_type", "last_modified_at"] {
            if let v = metadata[key] { payload[key] = v }
        }
        if let v = metadata["event_id"] { payload["event_id"] = v }
        if let v = metadata["duration_s"] { payload["duration_s"] = v }
        if let v = metadata["distance_m"] { payload["distance_m"] = v }
        if let v = metadata["avg_bpm"] { payload["avg_bpm"] = v }
        if let v = metadata["hr_coverage"] { payload["hr_coverage"] = v }
        if let v = metadata["steps"] { payload["steps"] = v }
        if let v = metadata["laps"] { payload["laps"] = v }
        payload["track"] = track
        return payload
    }

    func flushPending() {
        // Snapshot and clear under the lock, then dispatch outside it: the
        // dispatch re-enters this queue to re-buffer a run, and a `sync` from
        // inside a held block would deadlock.
        let snapshot = state.sync { () -> [[String: Any]] in
            guard _refusedRetries < Self.maxRefusedRetries else { return [] }
            let snapshot = _pending
            _pending.removeAll()
            return snapshot
        }
        for payload in snapshot { dispatch(payload) }
    }

    func dispatch(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let channel = self.methodChannel else {
                // The engine is not up yet. That is not a refusal, so it must
                // not spend the retry budget a real refusal is bounded by.
                self.buffer(payload)
                return
            }
            channel.invokeMethod("run", arguments: payload) { [weak self] result in
                // If Dart returned false, the Supabase write failed — re-queue
                // for the next watch contact so we don't drop the run.
                if let ok = result as? Bool, !ok {
                    self?.requeueRefused(payload)
                }
            }
        }
    }

    private func buffer(_ payload: [String: Any]) {
        state.sync { _pending.append(payload) }
    }

    func requeueRefused(_ payload: [String: Any]) {
        state.sync {
            _refusedRetries += 1
            _pending.append(payload)
        }
    }
}
