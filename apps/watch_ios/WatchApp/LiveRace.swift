import Foundation

/// Where a race can be, spelled as `race_sessions.status` spells it.
///
/// Only `armed` and `running` put anything on a wrist. The other two are how
/// a race ENDS: there is nothing left to show and nothing left to send, so
/// they clear the wrist rather than becoming a state it sits in.
enum RaceStatus: String, Codable {
    case armed
    case running
    case finished
    case cancelled
}

/// A live race the paired iPhone armed on this wrist.
///
/// The organiser arms, starts and ends a race from web or the phone; nothing
/// here can advance it. The phone pushes each transition over the same
/// `WCSession` the route push rides (`WatchConnectivityManager.receive(_:)`),
/// and this app's whole part is to show which of the three states the race is
/// in, ping while it runs, and report a finisher time once.
struct LiveRace: Codable, Equatable {
    let eventId: String
    /// Opaque here: echoed back verbatim on every ping and on the finisher
    /// report, never parsed. `race_sessions` is keyed on `(event_id,
    /// instance_start)` and the phone owns that timestamp's serialization, so
    /// a watch that re-formatted it would be a second place for the key to
    /// drift — and a ping keyed to a row that does not exist is silently
    /// dropped by PostgREST rather than reported.
    let instanceStart: String
    let status: RaceStatus
    let eventTitle: String?

    var isArmed: Bool { status == .armed }
    var isRunning: Bool { status == .running }

    /// Read a race out of a `WCSession` payload, or nil when the payload
    /// carries none or one this watch will not act on.
    ///
    /// Fail-closed like `ArmedRoute.decode`: a status word this build does
    /// not know, or a missing key, drops the whole push. The alternative is
    /// worse than doing nothing — a partly-read push whose status defaulted
    /// would either clear a race that is still running or ping a race that
    /// has ended.
    static func decode(_ payload: [String: Any]) -> LiveRace? {
        guard let eventId = payload["race_event_id"] as? String, !eventId.isEmpty,
              let instanceStart = payload["race_instance_start"] as? String,
              !instanceStart.isEmpty,
              let rawStatus = payload["race_status"] as? String,
              let status = RaceStatus(rawValue: rawStatus)
        else { return nil }
        let title = (payload["race_event_title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LiveRace(
            eventId: eventId,
            instanceStart: instanceStart,
            status: status,
            eventTitle: (title?.isEmpty ?? true) ? nil : title
        )
    }
}

/// One accepted GPS fix, as live race mode cares about it.
struct RacePingSample: Equatable {
    let latitude: Double
    let longitude: Double
    let distanceMetres: Double
    let elapsedSeconds: Int
    let bpm: Int?
    /// `ProcessInfo.systemUptime`, never a wall clock. The cadence gate below
    /// is the only thing keeping the spectator map's dot rate honest, and an
    /// NTP step backwards on a `Date` clock would stall it for the size of
    /// the step.
    let uptime: TimeInterval
}

/// A finished run, as live race mode cares about it.
struct RaceFinish: Equatable {
    let runId: String
    let durationSeconds: Int
    let distanceMetres: Double
}

/// The two payloads this watch sends the phone. Flat plist values, the way
/// the route push is flat — and prefixed, so the phone's single inbound
/// handler can tell them apart from each other and from a run hand-off
/// without a discriminator key that could go missing.
enum RaceEnvelope {
    static func ping(race: LiveRace, sample: RacePingSample) -> [String: Any] {
        var payload: [String: Any] = [
            "race_ping_event_id": race.eventId,
            "race_ping_instance_start": race.instanceStart,
            "race_ping_lat": sample.latitude,
            "race_ping_lng": sample.longitude,
            "race_ping_distance_m": sample.distanceMetres,
            "race_ping_elapsed_s": sample.elapsedSeconds
        ]
        // Omitted rather than sent as 0, for the reason `avg_bpm` is: nothing
        // measured a heart rate is a different statement from a heart rate of
        // zero, and the spectator leaderboard renders what it is given.
        if let bpm = sample.bpm, bpm > 0 { payload["race_ping_bpm"] = bpm }
        return payload
    }

    static func result(race: LiveRace, finish: RaceFinish) -> [String: Any] {
        [
            "race_result_event_id": race.eventId,
            "race_result_instance_start": race.instanceStart,
            "race_result_run_id": finish.runId,
            "race_result_duration_s": finish.durationSeconds,
            "race_result_distance_m": finish.distanceMetres
        ]
    }
}

/// The Arm / Go / End state machine, as a value.
///
/// Wear OS derives the same three states by polling `race_sessions` itself
/// (`RaceSessionClient.fetchActive`); this watch is told them by the phone
/// instead, because `apps/watch_ios/CLAUDE.md` keeps the Supabase surface off
/// the wrist. The states and what the wrist does in each are the same on both
/// — a spectator watching one live link must see the same thing whichever
/// wrist the runner wore.
struct LiveRaceState: Equatable {
    /// Wear OS's `maybePushRacePing` and the phone's `RaceController.pushPing`
    /// both debounce to this. It is a property of the spectator map, not of a
    /// device, so all three carry the same number.
    static let pingIntervalSeconds: TimeInterval = 10

    private(set) var race: LiveRace?
    private(set) var lastPingUptime: TimeInterval?

    init(race: LiveRace? = nil) {
        self.race = race?.isArmed == true || race?.isRunning == true ? race : nil
    }

    /// Apply an Arm / Go / End push. Returns whether anything the wrist shows
    /// or sends actually changed, so a re-push of the same state costs no
    /// republish and no disk write.
    @discardableResult
    mutating func apply(_ incoming: LiveRace?) -> Bool {
        let next: LiveRace?
        switch incoming?.status {
        case .armed, .running:
            next = incoming
        case .finished, .cancelled, .none:
            next = nil
        }
        guard next != race else { return false }
        // GO resets the cadence so the first ping of the race goes out on the
        // next fix, rather than up to ten seconds into a race the runner has
        // already started.
        if next?.isRunning != race?.isRunning { lastPingUptime = nil }
        race = next
        return true
    }

    /// The ping this fix earns, or nil when it earns none — the race is not
    /// running, the fix is not usable, or the last ping is too recent.
    mutating func ping(_ sample: RacePingSample) -> [String: Any]? {
        guard let race, race.isRunning else { return nil }
        guard sample.latitude.isFinite, sample.longitude.isFinite,
              sample.distanceMetres.isFinite, sample.distanceMetres >= 0
        else { return nil }
        if let last = lastPingUptime,
           sample.uptime >= last,
           sample.uptime - last < Self.pingIntervalSeconds {
            return nil
        }
        lastPingUptime = sample.uptime
        return RaceEnvelope.ping(race: race, sample: sample)
    }

    /// The finisher time this run earns, or nil when it earns none, and the
    /// race is forgotten either way once it has one.
    ///
    /// Wear clears its own `activeRace` at the same point: the runner has
    /// finished, so the next poll finding the race still `running` on the
    /// server is about other people. Clearing here also makes the report
    /// once-only, which matters because a second `stop()` on the same run
    /// would otherwise re-submit it.
    mutating func finish(_ finish: RaceFinish) -> [String: Any]? {
        guard let race, race.isRunning else { return nil }
        self.race = nil
        lastPingUptime = nil
        return RaceEnvelope.result(race: race, finish: finish)
    }
}

/// The armed race's home between the phone's push and the run that follows
/// it. Same reason `ArmedRouteStore` exists: a push lands while the app is
/// backgrounded, and the runner opens it minutes later.
enum LiveRaceStore {
    private static let key = "live_race_v1"

    static func load(defaults: UserDefaults = .standard) -> LiveRace? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LiveRace.self, from: data)
    }

    static func save(_ race: LiveRace, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(race) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// Finisher times `WCSession` could not be handed, kept until it can.
///
/// The run hand-off has WCSession's own durable outbox behind it, but that
/// outbox only accepts work once the session is `.activated`, and a race can
/// end on a watch whose session has gone `.inactive`. A finisher's official
/// time is the one thing in this feature that cannot simply be dropped, so it
/// goes to disk instead — the wrist's copy of the phone's `PendingRaceResult`
/// queue. Replaying one is idempotent: `submitEventResult` upserts on
/// `(event_id, instance_start, user_id)`.
enum PendingRaceResultStore {
    private static let key = "pending_race_results_v1"

    /// Matches the phone's `kPendingRaceResultsMax`. A finisher time is one
    /// row per race, so the cap only exists so a permanently-failing hand-off
    /// cannot grow the stored list without limit. Oldest drop first.
    static let maxEntries = 20

    static func append(_ payload: [String: Any], defaults: UserDefaults = .standard) {
        var queued = load(defaults: defaults)
        // A re-run of the same race replaces its earlier time rather than
        // queueing a second row the upsert would collide on.
        let eventId = payload["race_result_event_id"] as? String
        let instance = payload["race_result_instance_start"] as? String
        queued.removeAll {
            $0["race_result_event_id"] as? String == eventId
                && $0["race_result_instance_start"] as? String == instance
        }
        queued.append(payload)
        if queued.count > maxEntries { queued.removeFirst(queued.count - maxEntries) }
        defaults.set(queued, forKey: key)
    }

    /// Everything queued, removed from the store in the same call. A caller
    /// that fails to send them is expected to append them again — leaving
    /// them would mean draining the same list twice on the next activation.
    static func drain(defaults: UserDefaults = .standard) -> [[String: Any]] {
        let queued = load(defaults: defaults)
        if !queued.isEmpty { defaults.removeObject(forKey: key) }
        return queued
    }

    private static func load(defaults: UserDefaults) -> [[String: Any]] {
        (defaults.array(forKey: key) as? [[String: Any]]) ?? []
    }
}

/// The recorder's seam to live race mode.
///
/// Both halves are auxiliary (L4) network effects and both default to doing
/// nothing, so `WorkoutManager` records with no transport wired at all. The
/// recorder hands a value across and reads nothing back: there is no return
/// value a failed race effect could use to reach the run, which is the whole
/// point of the shape (`docs/architecture/conventions.md` § Layered
/// resilience).
struct LiveRaceRelay {
    var ping: (RacePingSample) -> Void = { _ in }
    var finish: (RaceFinish) -> Void = { _ in }
}

/// What the pre-run race banner says. Pure, so the decision to show it is
/// made in one place and tested without a view.
enum RaceBanner {
    enum Phase: Equatable {
        case armed
        case live
    }

    static func phase(for race: LiveRace?) -> Phase? {
        switch race?.status {
        case .armed: return .armed
        case .running: return .live
        case .finished, .cancelled, .none: return nil
        }
    }

    /// The event's name, or nil when the push carried none and the banner
    /// should fall back to the localized word for an event.
    static func title(for race: LiveRace?) -> String? {
        guard let title = race?.eventTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        return title
    }
}
