import Flutter
import Foundation
import WatchConnectivity

/// Receives finished runs from the paired Apple Watch via
/// `WCSession.transferFile(_:metadata:)` and forwards them to Dart via
/// the `run_app/watch_ingest` method channel, and carries the opposite
/// direction — a route the runner picked on the phone, pushed to the watch
/// over `run_app/watch_route`, and the runner's unit + audio-cue preferences
/// over `run_app/watch_prefs`.
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

    /// A run Dart keeps refusing is re-dispatched on every watch contact, so
    /// without a ceiling a permanently-failing payload would spend a dispatch
    /// per activation and per received file for the life of the process. Past
    /// the ceiling the runs stay buffered — dropping them is the worse failure
    /// — and retrying resumes when a fresh engine attaches.
    static let maxRefusedRetries = 8

    /// `pending` and the ingest channel are touched from three queues: the
    /// WCSession delegate queue, the main queue, and the method channel's reply
    /// callback. Unsynchronised access to an `Array` across queues corrupts it.
    private let state = DispatchQueue(label: "com.threkir.watch-ingest.state")
    private var _methodChannel: FlutterMethodChannel?
    private var _pending: [[String: Any]] = []
    private var _refusedRetries = 0

    private var routeChannel: FlutterMethodChannel?
    private var prefsChannel: FlutterMethodChannel?

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
        let prefs = FlutterMethodChannel(
            name: "run_app/watch_prefs",
            binaryMessenger: binaryMessenger
        )
        prefs.setMethodCallHandler { call, result in
            self.handlePrefsCall(call, result: result)
        }
        prefsChannel = prefs
        state.sync {
            _methodChannel = ingest
            // A fresh engine is a genuinely new chance at the write, so a run
            // stranded by the retry ceiling gets tried again rather than
            // sitting in the buffer until the process dies.
            _refusedRetries = 0
        }
        flushPending()
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Preference push (phone -> watch)

    /// `updateApplicationContext`, not `transferUserInfo`: the distance unit
    /// and the audio-cue switch are latest-value STATE, not events. The
    /// context is a single slot the phone overwrites, so a runner flipping a
    /// switch six times costs one delivery, and WCSession hands the watch
    /// whatever was last written the moment the two are next in contact —
    /// including on the watch's own cold launch, via
    /// `receivedApplicationContext`. A queue would replay every intermediate
    /// value and a `sendMessage` would have dropped them all, which is how a
    /// runner ended up unable to silence the wrist from anywhere.
    private func handlePrefsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "available":
            result(Self.canPushRoute())
        case "push":
            guard let args = call.arguments as? [String: Any],
                  let context = Self.prefsContext(from: args) else {
                result(FlutterError(
                    code: "bad_prefs",
                    message: "Preference payload rejected",
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
            do {
                try WCSession.default.updateApplicationContext(context)
                result(nil)
            } catch {
                result(FlutterError(
                    code: "push_failed",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Re-check the shape here as well as on the watch, for the same reason
    /// `routeUserInfo` does — and one stronger. The application context is
    /// RETAINED by the system and re-offered on every contact, so a value the
    /// watch's fail-closed decode refuses is refused on every contact for as
    /// long as it stands, against a runner who was told their preference
    /// applied.
    static func prefsContext(from args: [String: Any]) -> [String: Any]? {
        guard let unit = args["preferred_unit"] as? String,
              unit == "km" || unit == "mi",
              let audioCues = args["audio_cues"] as? Bool
        else { return nil }
        return ["preferred_unit": unit, "audio_cues": audioCues]
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

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        flushPending()
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
